# ISO镜像USB启动修复指南

## 问题描述

自制的 NiuLink ISO 镜像在虚拟机中能正常启动，但使用 BalenaEtcher 等工具写入物理 USB 设备时会报错"找不到分区表"，无法在物理机上启动。

## 问题分析

通过对比标准 CentOS 镜像和 NiuLink 镜像的结构差异，发现问题根源：

### 标准镜像特征 (CentOS)
```bash
# 分区表信息
Disk identifier: 0x6acc9bba
Device                            Boot Start     End Sectors  Size Id Type
CentOS-7-x86_64-Minimal-2009.iso1 *        0 1992703 1992704  973M  0 Empty
CentOS-7-x86_64-Minimal-2009.iso2        444   18043   17600  8.6M ef EFI

# 启动记录
Boot record: El Torito, MBR isohybrid cyl-align-on GPT
```

### 问题镜像特征 (NiuLink)
```bash
# 完全没有分区表
Disk NiuLinkOS-xxx.iso: 3.18 GiB, 3418292224 bytes, 6676352 sectors
# 没有分区信息

# 启动记录
Boot record: El Torito  # 缺少 MBR isohybrid 支持
```

## 解决方案

使用 `xorriso` 工具为 ISO 镜像添加 isohybrid 支持和 MBR 分区表：

```bash
# 修复命令
xorriso -indev 原始镜像.iso \
        -outdev 修复后镜像.iso \
        -boot_image any replay \
        -boot_image isolinux partition_table=on \
        -commit
```

## 修复效果验证

修复后的镜像具备以下特征：

```bash
# 具有正常的分区表
Disk identifier: 0x2c39a16b
Device               Boot Start     End Sectors  Size Id Type
NiuLinkOS-fixed.iso1 *        0 6678143 6678144  3.2G 17 Hidden HPFS/NTFS

# 完整的启动支持
Boot record: El Torito, MBR cyl-align-on
El Torito img opts: boot-info-table isohybrid-suitable
```

## 验证方法

1. **检查分区表结构**
   ```bash
   fdisk -l 镜像文件.iso
   ```

2. **检查启动信息**
   ```bash
   xorriso -indev 镜像文件.iso -report_el_torito plain
   ```

3. **检查 MBR 区域**
   ```bash
   hexdump -C 镜像文件.iso | head -2
   ```

## 工具要求

- `xorriso` 1.5.4 或更高版本
- 支持 El Torito 和 isohybrid 功能

## 注意事项

1. 修复过程会重新生成整个镜像文件，需要足够的磁盘空间
2. 修复后的镜像大小可能略有增加（由于柱面对齐）
3. 保持原有的 BIOS 和 UEFI 双启动支持不变
4. 修复后的镜像完全兼容物理机和虚拟机启动

## 常见问题

**Q: 为什么虚拟机能启动但物理机不能？**
A: 虚拟机通常更宽容，可以直接从 ISO 文件系统启动，而物理机需要标准的 MBR/GPT 分区表结构。

**Q: 修复后的镜像是否还能在虚拟机中使用？**
A: 是的，修复后的镜像同时支持虚拟机和物理机启动。

**Q: 是否会影响原有的启动菜单和功能？**
A: 不会，修复只是添加了 USB 启动所需的分区表结构，不改变内部文件系统和启动逻辑。

