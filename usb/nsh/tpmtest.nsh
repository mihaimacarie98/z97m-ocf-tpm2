@echo -off
echo ============================================
echo  TPM2_Startup + SelfTest - proves chip works
echo ============================================
echo -- request locality 0
mm FED40000 0x02 -MMIO -w 1 -n
stall 100000
echo -- set commandReady
mm FED40018 0x40 -MMIO -w 1 -n
stall 100000
echo -- write TPM2_Startup(CLEAR) to FIFO
mm FED40024 0x80 -MMIO -w 1 -n
mm FED40024 0x01 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x0C -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x01 -MMIO -w 1 -n
mm FED40024 0x44 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
echo -- execute
mm FED40018 0x20 -MMIO -w 1 -n
stall 300000
echo -- STARTUP response (bytes 7-10 = 00 00 00 00 means SUCCESS):
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
echo ============================================
echo -- now SelfTest
mm FED40018 0x40 -MMIO -w 1 -n
stall 100000
mm FED40024 0x80 -MMIO -w 1 -n
mm FED40024 0x01 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x0B -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x00 -MMIO -w 1 -n
mm FED40024 0x01 -MMIO -w 1 -n
mm FED40024 0x43 -MMIO -w 1 -n
mm FED40024 0x01 -MMIO -w 1 -n
mm FED40018 0x20 -MMIO -w 1 -n
stall 500000
echo -- SELFTEST response (bytes 7-10 = 00 00 00 00 means SUCCESS):
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
echo -- release
mm FED40018 0x40 -MMIO -w 1 -n
mm FED40000 0x20 -MMIO -w 1 -n
echo ============================================
echo  Photograph BOTH response blocks.
echo ============================================
