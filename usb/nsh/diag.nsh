@echo -off
echo "============================================"
echo "TPM interface/interrupt diagnostic"
echo "============================================"
echo "ACCESS (0x00):"
mm FED40000 -MMIO -w 1 -n
echo "INT_ENABLE (0x08) - bit31 set = firmware using interrupts:"
mm FED40008 -MMIO -w 4 -n
echo "INT_VECTOR (0x0C) - nonzero = an IRQ was assigned:"
mm FED4000C -MMIO -w 1 -n
echo "INT_STATUS (0x10):"
mm FED40010 -MMIO -w 4 -n
echo "INTF_CAPABILITY (0x14) - what the chip says it supports:"
mm FED40014 -MMIO -w 4 -n
echo "STS (0x18):"
mm FED40018 -MMIO -w 4 -n
echo "INTERFACE_ID (0x30) - FIFO vs CRB selector:"
mm FED40030 -MMIO -w 4 -n
echo "DID_VID (0xF00):"
mm FED40F00 -MMIO -w 4 -n
echo "RID (0xF04):"
mm FED40F04 -MMIO -w 1 -n
echo "============================================"
echo "Photograph all values."
echo "============================================"
