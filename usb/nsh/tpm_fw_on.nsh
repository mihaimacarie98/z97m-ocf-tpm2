@echo -off
echo Firmware TPM support ON, TPM state off: 0x26=1 0x21=0 0x4A1=0 0x33=2
echo (may cause an intermittent freeze at the splash screen - press reset and it gets through)
setup_var.efi Setup:0x26=0x1 Setup:0x21=0x0 Setup:0x4A1=0x0 Setup:0x33=0x2
setup_var.efi Setup:0x26 Setup:0x21 Setup:0x33 Setup:0x4A1
echo Done. Type: reset
