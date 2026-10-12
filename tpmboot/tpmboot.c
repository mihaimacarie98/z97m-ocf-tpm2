/* tpmboot.efi v3 - pre-boot TPM 2.0 shim (Z97M OC Formula, SLB9665 TIS @0xFED40000)
 * 0) if the TPM reads 0xFFFFFFFF, open the PCH LPC decode window for 0xFED40000 (LGMR)
 * 1) TPM2_Startup(CLEAR)+SelfTest over TIS (polling)  2) install TPM2 ACPI table (rev3, StartMethod 6)
 * 3) optional one-shot TPM2_Clear if \EFI\tpmboot\clear exists on the ESP (file is deleted after)
 * 4) chain-load \EFI\Microsoft\Boot\bootmgfw.efi.  ALWAYS boots Windows even if TPM steps fail. */
#include <efi.h>
#include <efilib.h>
#define TPM_BASE 0xFED40000ULL
#define TIS_ACCESS (TPM_BASE+0x00)
#define TIS_STS    (TPM_BASE+0x18)
#define TIS_FIFO   (TPM_BASE+0x24)
#define TIS_DIDVID (TPM_BASE+0xF00)
#define ACC_ACTIVE 0x20
#define ACC_REQUEST 0x02
#define STS_VALID 0x80
#define STS_CMDREADY 0x40
#define STS_GO 0x20
#define STS_DATAAVAIL 0x10
static inline UINT8 r8(UINT64 a){return *(volatile UINT8*)(UINTN)a;}
static inline UINT32 r32(UINT64 a){return *(volatile UINT32*)(UINTN)a;}
static inline void w8(UINT64 a,UINT8 v){*(volatile UINT8*)(UINTN)a=v;}
static void ms(UINTN n){uefi_call_wrapper(BS->Stall,1,n*1000);}
static inline UINT32 inl_(UINT16 p){UINT32 v;__asm__ volatile("inl %1,%0":"=a"(v):"Nd"(p));return v;}
static inline void outl_(UINT16 p,UINT32 v){__asm__ volatile("outl %0,%1"::"a"(v),"Nd"(p));}
#define LPC_CFG(off) (0x80000000u|(31u<<11)|((off)&0xFCu))   /* bus0 dev31 fn0 = PCH LPC bridge */
static UINT32 pci_rd(UINT32 off){outl_(0xCF8,LPC_CFG(off));return inl_(0xCFC);}
static void pci_wr(UINT32 off,UINT32 v){outl_(0xCF8,LPC_CFG(off));outl_(0xCFC,v);}
/* make 0xFED40000 reachable on LPC if the firmware left it undecoded (TPM support off in setup) */
static UINT32 lpc_enable_tpm_decode(void){
    UINT32 cmd=pci_rd(0x04), lgmr=pci_rd(0x98);
    Print(L"tpmboot: LPC cmd=%04x LGMR=%08x -> enabling mem decode + LGMR window @FED40000\n",cmd&0xFFFF,lgmr);
    if(!(cmd&2))pci_wr(0x04,(cmd|2));
    pci_wr(0x98,0xFED40000u|1u);
    ms(10);
    return r32(TIS_DIDVID);
}

static BOOLEAN wait_sts(UINT8 m,UINTN loops){while(loops--){if((r8(TIS_STS)&m)==m)return TRUE;ms(1);}return FALSE;}
static UINT32 burst(void){return (r32(TIS_STS)>>8)&0xFFFF;}
static UINT32 tpm_cmd(const UINT8*cmd,UINTN len){
    UINT8 resp[64];UINTN i,rlen;
    w8(TIS_ACCESS,ACC_REQUEST);
    for(i=0;i<200&&!(r8(TIS_ACCESS)&ACC_ACTIVE);i++)ms(1);
    if(!(r8(TIS_ACCESS)&ACC_ACTIVE))return 0xFFFFFFFF;
    w8(TIS_STS,STS_CMDREADY);
    if(!wait_sts(STS_CMDREADY,500))return 0xFFFFFFFF;
    for(i=0;i<len;i++){UINTN s=0;while(burst()==0&&s++<2000)uefi_call_wrapper(BS->Stall,1,100);w8(TIS_FIFO,cmd[i]);}
    w8(TIS_STS,STS_GO);
    if(!wait_sts(STS_VALID|STS_DATAAVAIL,5000))return 0xFFFFFFFF;
    for(rlen=0;rlen<sizeof resp&&(r8(TIS_STS)&STS_DATAAVAIL);rlen++)resp[rlen]=r8(TIS_FIFO);
    w8(TIS_STS,STS_CMDREADY); w8(TIS_ACCESS,ACC_ACTIVE);
    if(rlen<10)return 0xFFFFFFFF;
    return ((UINT32)resp[6]<<24)|((UINT32)resp[7]<<16)|((UINT32)resp[8]<<8)|resp[9];
}
#define EFI_ACPI_TABLE_PROTOCOL_GUID {0xffe06bdd,0x6107,0x46a6,{0x7b,0xb2,0x5a,0x9c,0x7e,0xc5,0x27,0x5c}}
typedef struct _EFI_ACPI_TABLE_PROTOCOL EFI_ACPI_TABLE_PROTOCOL;
typedef EFI_STATUS(EFIAPI*EFI_ACPI_TABLE_INSTALL)(EFI_ACPI_TABLE_PROTOCOL*,VOID*,UINTN,UINTN*);
typedef EFI_STATUS(EFIAPI*EFI_ACPI_TABLE_UNINSTALL)(EFI_ACPI_TABLE_PROTOCOL*,UINTN);
struct _EFI_ACPI_TABLE_PROTOCOL{EFI_ACPI_TABLE_INSTALL InstallAcpiTable;EFI_ACPI_TABLE_UNINSTALL UninstallAcpiTable;};
#pragma pack(1)
typedef struct{CHAR8 Signature[4];UINT32 Length;UINT8 Revision;UINT8 Checksum;CHAR8 OemId[6];CHAR8 OemTableId[8];UINT32 OemRevision;CHAR8 CreatorId[4];UINT32 CreatorRevision;UINT16 PlatformClass;UINT16 Reserved;UINT64 ControlAreaAddress;UINT32 StartMethod;}TPM2_TABLE;
#pragma pack()
static EFI_STATUS install_tpm2_table(void){
    EFI_GUID g=EFI_ACPI_TABLE_PROTOCOL_GUID;EFI_ACPI_TABLE_PROTOCOL*acpi=NULL;
    EFI_STATUS st=uefi_call_wrapper(BS->LocateProtocol,3,&g,NULL,(VOID**)&acpi);
    if(EFI_ERROR(st)||!acpi)return EFI_ERROR(st)?st:EFI_NOT_FOUND;
    TPM2_TABLE t;UINT8*p=(UINT8*)&t;UINTN i,key=0;UINT8 sum=0;SetMem(&t,sizeof t,0);
    CopyMem(t.Signature,"TPM2",4);t.Length=sizeof t;t.Revision=3;CopyMem(t.OemId,"ALASKA",6);CopyMem(t.OemTableId,"A M I   ",8);
    t.OemRevision=0x01072009;CopyMem(t.CreatorId,"AMI ",4);t.CreatorRevision=0x00010013;t.PlatformClass=0;t.ControlAreaAddress=0;t.StartMethod=6;
    for(i=0;i<sizeof t;i++)sum+=p[i];t.Checksum=(UINT8)(0x100-sum);
    return uefi_call_wrapper(acpi->InstallAcpiTable,4,acpi,&t,sizeof t,&key);
}
static void one_shot_clear(EFI_FILE_HANDLE root){
    static const UINT8 clear[]={0x80,0x02,0,0,0,0x1B,0,0,0x01,0x26,0x40,0,0,0x0C,0,0,0,0x09,0x40,0,0,0x09,0,0,0,0,0};
    EFI_FILE_HANDLE f;
    if(EFI_ERROR(uefi_call_wrapper(root->Open,5,root,&f,L"\\EFI\\tpmboot\\clear",EFI_FILE_MODE_READ|EFI_FILE_MODE_WRITE,0)))return;
    Print(L"tpmboot: clear flag found -> TPM2_Clear rc=%08x\n",tpm_cmd(clear,sizeof clear));
    uefi_call_wrapper(f->Delete,1,f);
}
static EFI_STATUS chainload_windows(EFI_HANDLE image){
    EFI_GUID fsg=SIMPLE_FILE_SYSTEM_PROTOCOL;EFI_HANDLE*h=NULL;UINTN n=0,i;
    EFI_STATUS st=uefi_call_wrapper(BS->LocateHandleBuffer,5,ByProtocol,&fsg,NULL,&n,&h);
    if(EFI_ERROR(st))return st;
    for(i=0;i<n;i++){
        EFI_FILE_IO_INTERFACE*fs;EFI_FILE_HANDLE root,f;
        if(EFI_ERROR(uefi_call_wrapper(BS->HandleProtocol,3,h[i],&fsg,(VOID**)&fs)))continue;
        if(EFI_ERROR(uefi_call_wrapper(fs->OpenVolume,2,fs,&root)))continue;
        if(EFI_ERROR(uefi_call_wrapper(root->Open,5,root,&f,L"\\EFI\\Microsoft\\Boot\\bootmgfw.efi",EFI_FILE_MODE_READ,0))){uefi_call_wrapper(root->Close,1,root);continue;}
        uefi_call_wrapper(f->Close,1,f);
        one_shot_clear(root);
        uefi_call_wrapper(root->Close,1,root);
        EFI_DEVICE_PATH*dp=FileDevicePath(h[i],L"\\EFI\\Microsoft\\Boot\\bootmgfw.efi");EFI_HANDLE img=NULL;
        st=uefi_call_wrapper(BS->LoadImage,6,FALSE,image,dp,NULL,0,&img);
        if(EFI_ERROR(st)){Print(L"tpmboot: LoadImage: %r\n",st);continue;}
        return uefi_call_wrapper(BS->StartImage,3,img,NULL,NULL);
    }
    return EFI_NOT_FOUND;
}
EFI_STATUS EFIAPI efi_main(EFI_HANDLE image,EFI_SYSTEM_TABLE*systab){
    static const UINT8 startup[]={0x80,0x01,0,0,0,0x0C,0,0,0x01,0x44,0,0};
    static const UINT8 selftest[]={0x80,0x01,0,0,0,0x0B,0,0,0x01,0x43,0x01};
    InitializeLib(image,systab);
    UINT32 id=r32(TIS_DIDVID);
    Print(L"tpmboot v3: DID_VID=%08x\n",id);
    if(id==0xFFFFFFFF||id==0){ id=lpc_enable_tpm_decode(); Print(L"tpmboot: after LPC decode enable DID_VID=%08x\n",id); }
    if(id==0xFFFFFFFF||id==0){Print(L"tpmboot: TPM still not reachable - booting Windows (set Setup:0x26=0x1 as fallback)\n");ms(4000);}
    else{
        UINT32 rc=tpm_cmd(startup,sizeof startup);
        Print(L"tpmboot: Startup(CLEAR) rc=%08x %a\n",rc,rc==0?"OK":(rc==0x100?"(already started - OK)":"<- unexpected"));
        rc=tpm_cmd(selftest,sizeof selftest);
        Print(L"tpmboot: SelfTest rc=%08x %a\n",rc,rc==0?"OK":"");
        EFI_STATUS st=install_tpm2_table();
        Print(L"tpmboot: TPM2 ACPI table: %r\n",st);
        ms(3500);
    }
    EFI_STATUS st=chainload_windows(image);
    Print(L"tpmboot: could not start Windows Boot Manager: %r\n",st);ms(8000);
    return st;
}
