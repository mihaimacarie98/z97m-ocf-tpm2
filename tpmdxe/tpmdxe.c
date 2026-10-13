/* TpmBootDxe - in-firmware TPM 2.0 bring-up for the Z97M OC Formula (SLB9665 TIS @0xFED40000)
 * DXE driver version of tpmboot.efi, dispatched from the BIOS's DXE volume once
 * EFI_ACPI_TABLE_PROTOCOL exists (depex).  Every boot:
 * 0) if the TPM reads 0xFFFFFFFF, open the PCH LPC decode window for 0xFED40000 (LGMR)
 * 1) TPM2_Startup(CLEAR)+SelfTest over TIS (polling, bounded waits)
 * 2) install the TPM2 ACPI table (rev3, StartMethod 6)
 * 3) publish a volatile variable TpmBootDxe-{78c18031-...} = {DID_VID, Startup rc, table status}
 *    so the USB stick's startup.nsh can detect V11 firmware (`dmpstore TpmBootDxe -guid ...`)
 * Never blocks boot: no TPM -> returns at once; every wait has a timeout.
 * Because it lives in flash, Secure Boot never checks it: no shim/MokManager needed. */
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
static void us(UINTN n){uefi_call_wrapper(BS->Stall,1,n);}
static void ms(UINTN n){us(n*1000);}
static inline UINT32 inl_(UINT16 p){UINT32 v;__asm__ volatile("inl %1,%0":"=a"(v):"Nd"(p));return v;}
static inline void outl_(UINT16 p,UINT32 v){__asm__ volatile("outl %0,%1"::"a"(v),"Nd"(p));}
#define LPC_CFG(off) (0x80000000u|(31u<<11)|((off)&0xFCu))   /* bus0 dev31 fn0 = PCH LPC bridge */
static UINT32 pci_rd(UINT32 off){outl_(0xCF8,LPC_CFG(off));return inl_(0xCFC);}
static void pci_wr(UINT32 off,UINT32 v){outl_(0xCF8,LPC_CFG(off));outl_(0xCFC,v);}

static BOOLEAN tpm_present(UINT32 id){return id!=0xFFFFFFFF&&id!=0;}
/* make 0xFED40000 reachable on LPC if the firmware left it undecoded (TPM support off in setup) */
static UINT32 lpc_enable_tpm_decode(void){
    UINT32 cmd=pci_rd(0x04);
    if((pci_rd(0x00)&0xFFFF)!=0x8086)return 0xFFFFFFFF;          /* not an Intel LPC bridge */
    if(!(cmd&2))pci_wr(0x04,cmd|2);
    pci_wr(0x98,0xFED40000u|1u);                                  /* LGMR: 64 KiB generic memory window */
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
    if(!wait_sts(STS_CMDREADY,500))goto fail;
    for(i=0;i<len;i++){
        UINTN s=0;
        while(burst()==0){if(++s>2000)goto fail;us(100);}
        w8(TIS_FIFO,cmd[i]);
    }
    w8(TIS_STS,STS_GO);
    if(!wait_sts(STS_VALID|STS_DATAAVAIL,3000))goto fail;
    for(rlen=0;rlen<sizeof resp&&(r8(TIS_STS)&STS_DATAAVAIL);rlen++)resp[rlen]=r8(TIS_FIFO);
    w8(TIS_STS,STS_CMDREADY); w8(TIS_ACCESS,ACC_ACTIVE);
    if(rlen<10)return 0xFFFFFFFF;
    return ((UINT32)resp[6]<<24)|((UINT32)resp[7]<<16)|((UINT32)resp[8]<<8)|resp[9];
fail:
    w8(TIS_STS,STS_CMDREADY); w8(TIS_ACCESS,ACC_ACTIVE);
    return 0xFFFFFFFF;
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
    for(i=0;i<sizeof t;i++)sum+=p[i];
    t.Checksum=(UINT8)(0x100-sum);
    return uefi_call_wrapper(acpi->InstallAcpiTable,4,acpi,&t,sizeof t,&key);
}

/* Chipset drivers that run after us may reprogram LPC decode; re-open the window right before
 * the OS loader starts.  Called by firmware, so it needs the MS calling convention. */
static __attribute__((ms_abi)) VOID on_ready_to_boot(EFI_EVENT ev,VOID*ctx){
    (void)ctx;
    if(!tpm_present(r32(TIS_DIDVID)))lpc_enable_tpm_decode();
    uefi_call_wrapper(BS->CloseEvent,1,ev);
}

/* volatile (gone at power-off), readable from the shell and from Windows */
static void report(UINT32 didvid,UINT32 rc,EFI_STATUS table){
    static EFI_GUID g={0x78c18031,0xb5ae,0x4112,{0xa6,0x35,0x70,0x28,0x5b,0x92,0x0a,0x2f}};
    UINT32 v[3]={didvid,rc,(UINT32)table};
    uefi_call_wrapper(RT->SetVariable,5,L"TpmBootDxe",&g,
        EFI_VARIABLE_BOOTSERVICE_ACCESS|EFI_VARIABLE_RUNTIME_ACCESS,sizeof v,v);
}

EFI_STATUS EFIAPI efi_main(EFI_HANDLE image,EFI_SYSTEM_TABLE*systab){
    static const UINT8 startup[]={0x80,0x01,0,0,0,0x0C,0,0,0x01,0x44,0,0};
    static const UINT8 selftest[]={0x80,0x01,0,0,0,0x0B,0,0,0x01,0x43,0x01};
    static EFI_GUID ready_to_boot={0x7ce88fb3,0x4bd7,0x4679,{0x87,0xa8,0xa8,0xd8,0xde,0xe5,0x0d,0x2b}};
    EFI_EVENT ev;
    InitializeLib(image,systab);
    UINT32 id=r32(TIS_DIDVID);
    BOOLEAN opened=FALSE;
    if(!tpm_present(id)){id=lpc_enable_tpm_decode();opened=TRUE;}
    if(!tpm_present(id)){report(id,0xFFFFFFFF,EFI_NOT_FOUND);return EFI_SUCCESS;}   /* no TPM module */
    UINT32 rc=tpm_cmd(startup,sizeof startup);
    if(rc!=0&&rc!=0x100){report(id,rc,EFI_NOT_READY);return EFI_SUCCESS;}           /* chip not answering: don't advertise it */
    tpm_cmd(selftest,sizeof selftest);
    report(id,rc,install_tpm2_table());
    if(opened)uefi_call_wrapper(BS->CreateEventEx,6,EVT_NOTIFY_SIGNAL,TPL_CALLBACK,on_ready_to_boot,NULL,&ready_to_boot,&ev);
    return EFI_SUCCESS;                                           /* stay resident for the callback */
}
