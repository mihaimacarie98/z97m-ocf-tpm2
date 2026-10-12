@echo -off
echo ============================================
echo  TPM2_Clear - resets SLB9665 internal state
echo ============================================
echo Step 1: request locality 0
mm FED40000 0x02 -MMIO -w 1 -n
stall 100000
echo Step 2: ACCESS reg (want bit 0x20 set, e.g. 0xA1):
mm FED40000 -MMIO -w 1 -n
echo Step 3: set commandReady
mm FED40018 0x40 -MMIO -w 1 -n
stall 100000
echo Step 3b: STS reg (want bit 0x40 set):
mm FED40018 -MMIO -w 1 -n
echo Step 4: write TPM2_Clear(PLATFORM) to FIFO
mm FED40024 0x80 -MMIO -w 1 -n
mm FED40024 0x02 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x1B -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x01 -MMIO -w 1 -n
mm FED40024 0x26 -MMIO -w 1 -n
mm FED40024 0x40 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x0C -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x09 -MMIO -w 1 -n
mm FED40024 0x40 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x09 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
echo Step 5: execute (tpmGo)
mm FED40018 0x20 -MMIO -w 1 -n
stall 300000
echo Step 6: STS (want dataAvail bit 0x10 set):
mm FED40018 -MMIO -w 4 -n
echo Step 7: response header - 10 bytes from FIFO.
echo   Bytes 7-10 are the result code. 00 00 00 00 = SUCCESS (cleared).
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
mm FED40024 -MMIO -w 1 -n
echo Step 8: release
mm FED40018 0x40 -MMIO -w 1 -n
mm FED40000 0x20 -MMIO -w 1 -n
echo ============================================
echo  Done. Photograph the response code bytes.
echo ============================================
