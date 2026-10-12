DefinitionBlock ("", "DSDT", 2, "ALASKA", "A M I", 0x00000001)
{
    Scope (_SB) {}
    Device (_SB.TPM)
    {
        Name (_HID, "MSFT0101")
        Name (_CID, EisaId ("PNP0C31"))
        Name (_UID, One)
        Name (_STR, Unicode ("TPM 2.0 Device"))
        Method (_STA, 0, NotSerialized) { Return (0x0F) }
        Name (_CRS, ResourceTemplate () { Memory32Fixed (ReadWrite, 0xFED40000, 0x00005000) })
    }
}
