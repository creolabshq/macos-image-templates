## Building Vanilla Image

To build `macos-sonoma-vanilla`:

```bash
packer build templates/vanilla-sonoma.pkr.hcl
```

Optionally, SIP can be disabled for each image by running the following commands:

```bash
packer build -var vm_name=sonoma-vanilla templates/disable-sip.pkr.hcl
```

## Building Base Image

```bash
packer build -var macos_version=sonoma templates/base.pkr.hcl
```

## Building Xcode Image

```bash
packer build -var macos_version=sonoma -var xcode_version="[15.4]" templates/xcode.pkr.hcl
```

## Building Expo Image

```bash
packer build -var cpu_count=8 -var memory_gb=16 -var macos_version=sequoia -var xcode_version="[16.2]" templates/expo.pkr.hcl
```
