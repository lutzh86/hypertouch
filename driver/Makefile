DRIVER_NAME := hypertouch40
KERNEL_SOURCE_DIR ?= /lib/modules/$(shell uname -r)/build

obj-m := $(DRIVER_NAME).o

modules:
	$(MAKE) -C $(KERNEL_SOURCE_DIR) M=$(PWD) modules

install: modules_install

modules_install:
	$(MAKE) -C $(KERNEL_SOURCE_DIR) M=$(PWD) modules_install
	depmod -a

clean:
	$(MAKE) -C $(KERNEL_SOURCE_DIR) M=$(PWD) clean
