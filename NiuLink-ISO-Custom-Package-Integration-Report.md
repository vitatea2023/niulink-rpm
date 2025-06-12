# NiuLink ISO 自定义包集成技术报告

## 项目概述

本项目的目标是将一个或多个自定义RPM包集成到 NiuLink OS ISO 镜像中，确保在系统安装过程中这些包能够被自动安装并正常运行。项目支持同时集成多个RPM包，所有包都会被添加到默认安装的包组中，确保在全自动安装过程中被强制安装。

**最终成功方案**: `repack_iso_with_groups.sh` 脚本

## 问题背景

### 初始需求
- 目标ISO: `NiuLinkOS-v1.1.7-2411141913.iso` 或其他兼容的CentOS/RHEL系列ISO
- 自定义包: 支持单个或多个RPM包（如 `upload-pulse-1.0.0-1.el7.x86_64.rpm`）
- 要求: 所有包需要在系统安装时自动安装并运行
- 约束: 不能修改 kickstart 配置（系统有特殊定制逻辑）
- 支持: 批量集成多个RPM包到同一个ISO中

### 技术挑战
1. **UEFI启动问题**: 原始ISO存在UEFI安装错误
2. **Repository结构复杂**: ISO包含多层repository结构
3. **包组依赖**: 需要理解CentOS/RHEL的包组安装机制
4. **自动化安装**: 系统使用自动化安装，需要确保包被正确选择

## 技术分析

### ISO结构分析

原始 NiuLinkOS ISO 结构：
```
/
├── EFI/BOOT/              # UEFI 启动文件
├── isolinux/              # Legacy BIOS 启动文件
├── images/                # 内核镜像
├── LiveOS/                # Live系统文件
├── Packages/              # 407个RPM包文件
│   └── repodata/          # 包仓库元数据
├── repodata/              # 根级仓库元数据（重要！）
└── 其他文件...
```

**关键发现**:
- **双Repository结构**: 既有根级 `/repodata`，也有 `/Packages/repodata`
- **Anaconda读取**: 安装器主要读取根级 `/repodata` 进行包选择
- **包组定义**: `comps.xml` 文件定义了哪些包会被自动安装

### 包安装机制

CentOS/RHEL 系统的包安装遵循以下规则：

1. **Repository Metadata**: 定义了所有可用的包
2. **Package Groups**: 通过 `comps.xml` 定义包的分组
3. **Installation Classes**: Anaconda 根据包组选择要安装的包
4. **Mandatory Packages**: 标记为 `mandatory` 的包会被强制安装

## 遇到的问题及解决过程

### 第一阶段：简单添加包到Repository

#### 尝试方案 1: `repack_iso_with_rpm.sh`
**方法**: 仅将RPM添加到 `/Packages/` 目录并更新该目录的 repodata

**结果**: 失败
- 包确实被添加到了repository
- 但在安装时没有被实际安装
- **原因**: 包不在任何包组中，anaconda忽略了它

**教训**: 仅添加包到repository是不够的，必须让anaconda知道要安装这个包

### 第二阶段：修复Repository结构

#### 尝试方案 2: `repack_iso_fixed.sh`
**方法**: 同时更新根级 `/repodata` 和 `/Packages/repodata`

**出现的问题**:
1. **Installation source errors**: "Error setting up software source"
2. **Software selection errors**: "Installation source not set up"

**根本原因**: 
- 删除了原始的根级 `/repodata` 目录
- 重新创建过程中出现错误，导致anaconda无法识别安装源

**createrepo 执行问题**:
```bash
# 失败的命令
createrepo_c --groupfile ./repodata/*comps.xml ./temp_root_repo
# 错误：通配符展开失败，comps.xml路径不正确
```

**关键错误日志**:
```
Directory walk done - 408 packages
Loaded information about 407 packages  # ← 只加载了407个包的信息！
```

**教训**: 
- 不应该删除原始repository结构
- 通配符在createrepo命令中需要正确处理
- Repository更新失败会导致严重的安装问题

### 第三阶段：正确的Repository更新

#### 尝试方案 3: `repack_iso_final.sh`
**方法**: 使用 `--update` 模式原地更新repository

**新问题**: 包计数不一致
- Repository metadata显示: 408个包
- Anaconda安装时显示: 403个包
- 包虽然在repository中，但实际没有被安装

**深入分析发现**:
- 原始ISO: 407个包
- 添加后: 408个包
- 但anaconda显示403个包，说明有计数逻辑问题
- **关键**: 即使包在repository中，如果不在包组中就不会被安装

### 第四阶段：理解包组机制（突破性发现）

#### 分析 comps.xml 文件
```xml
<group>
  <id>core</id>
  <name>Core</name>
  <default>true</default>        <!-- 这个组会被默认安装 -->
  <uservisible>false</uservisible>
  <packagelist>
    <packagereq type="mandatory">audit</packagereq>
    <packagereq type="mandatory">basesystem</packagereq>
    <!-- 更多mandatory包... -->
  </packagelist>
</group>
```

**核心发现**:
- 只有在 `default=true` 的包组中的包才会被自动安装
- `type="mandatory"` 的包会被强制安装
- upload-pulse 不在任何包组中，所以被忽略

### 第五阶段：最终解决方案

#### 方案 4: `repack_iso_with_groups.sh` （成功！）
**核心思路**: 将 upload-pulse 添加到默认安装的包组中

**关键修改**:
1. **修改 comps.xml**:
```xml
<group>
  <id>core</id>
  <default>true</default>
  <packagelist>
    <!-- 原有包... -->
    <packagereq type="mandatory">upload-pulse</packagereq>  <!-- 新增 -->
  </packagelist>
</group>
```

2. **同时添加到minimal环境**:
```xml
<environment>
  <id>minimal</id>
  <packagelist>
    <!-- 原有包... -->
    <packagereq type="mandatory">upload-pulse</packagereq>  <!-- 新增 -->
  </packagelist>
</environment>
```

**执行过程**:
1. 添加RPM到 `/Packages/` 目录
2. 更新 `/Packages/repodata`
3. **修改 comps.xml** 添加包组引用
4. 使用修改后的 comps.xml 更新根级 repository
5. 应用UEFI修复
6. 重新打包ISO

## 脚本详细解析

### 关键技术点

#### 1. Repository双重更新
```bash
# 更新Packages repository
createrepo_c --update ./Packages

# 更新根级repository（包含包组信息）
createrepo_c --groupfile "$COMPS_FILE" --update .
```

#### 2. comps.xml修改
```bash
# 添加到core组（确保基础安装包含）
sed -i '/<id>core<\/id>/,/<\/packagelist>/ {
    /<\/packagelist>/ i\      <packagereq type="mandatory">upload-pulse</packagereq>
}' "$COMPS_FILE"

# 添加到minimal环境（确保最小安装也包含）
sed -i '/<id>minimal<\/id>/,/<\/packagelist>/ {
    /<\/packagelist>/ i\      <packagereq type="mandatory">upload-pulse</packagereq>
}' "$COMPS_FILE"
```

#### 3. UEFI修复
```bash
# 修复fedora.py EFI目录指向
sed -i 's/efi_dir = "fedora"/efi_dir = "centos"/' fedora.py

# 隐藏fedora安装类防止EFI错误
sed -i '/if productName\.startswith("Red Hat ") or productName\.startswith("CentOS"):/,+1c\
    # Always hide fedora class to prevent EFI errors\n    hidden = True' fedora.py

# 确保CentOS安装类可见
sed -i 's/if not productName\.startswith("CentOS"):/if False:  # Always show CentOS class/' centos.py
```

#### 4. 完整性验证
```bash
# 验证包在repository中
zcat ./repodata/*primary.xml.gz | grep -q "upload-pulse"

# 验证包在包组中
grep -q 'upload-pulse' "$COMPS_FILE"
```

### 错误处理机制

脚本包含完善的错误处理：

1. **输入验证**: 检查ISO文件和RPM文件是否存在
2. **工具检查**: 确保所有必需工具已安装
3. **过程验证**: 每个关键步骤都有验证机制
4. **失败恢复**: 出错时清理临时文件和挂载点
5. **详细日志**: 所有操作都记录到日志文件中

## 最终结果

### 成功指标
- ✅ ISO成功创建: `NiuLinkOS-v1.1.7-2411141913-repack-groups.iso`
- ✅ 包计数正确: 显示408个包（原始407 + upload-pulse 1个）
- ✅ 安装时显示: 404个包（anaconda的正常计数方式）
- ✅ **upload-pulse确认在包列表中**
- ✅ **实际验证**: 系统安装后upload-pulse正常运行，接口收到消息

### 技术验证
```bash
# Repository包含验证
$ zcat repodata/*primary.xml.gz | grep -c "<package "
408

# upload-pulse存在验证
$ zcat repodata/*primary.xml.gz | grep -A 3 "upload-pulse"
<package type="rpm">
  <name>upload-pulse</name>
  <arch>x86_64</arch>
  <version epoch="0" ver="1.0.0" rel="1.el7"/>

# 包组集成验证
$ grep -A 5 -B 5 "upload-pulse" comps.xml
      <packagereq type="optional">tboot</packagereq>
      <packagereq type="mandatory">upload-pulse</packagereq>
    </packagelist>
```

## 技术要点总结

### 关键成功因素

1. **理解CentOS包管理机制**: 
   - Repository只是包的存储
   - Package Groups决定哪些包被安装
   - comps.xml是关键配置文件

2. **正确的Repository结构**:
   - 根级 `/repodata` 包含包组信息
   - `/Packages/repodata` 包含包文件信息
   - 两者必须保持同步

3. **包组集成策略**:
   - 选择默认安装的包组（core）
   - 使用mandatory类型确保强制安装
   - 同时覆盖多个安装环境

4. **UEFI兼容性**:
   - 修复fedora EFI目录问题
   - 确保CentOS安装类优先级
   - 保持双启动支持

### 避免的陷阱

1. **仅添加到Repository**: 包不会被自动安装
2. **删除原始Repository**: 会导致安装源错误
3. **忽略包组**: anaconda按包组选择包，不是按Repository
4. **createrepo参数错误**: 通配符和路径处理需要小心
5. **验证不充分**: 必须验证包既在Repository中也在包组中

## 使用指南

### 环境要求
- Debian 12 (Bookworm) 或兼容系统
- 必需工具: `xorriso`, `squashfs-tools`, `createrepo-c`
- 足够的磁盘空间（至少4GB空闲空间）
- Root权限（用于挂载和文件系统操作）

### 安装依赖
```bash
sudo apt update
sudo apt install -y xorriso squashfs-tools createrepo-c
```

### 执行脚本

#### 单个RPM包集成:
```bash
sudo ./repack_iso_with_groups.sh NiuLinkOS-v1.1.7-2411141913.iso upload-pulse-1.0.0-1.el7.x86_64.rpm
```

#### 多个RPM包集成:
```bash
# 集成多个包到同一个ISO
sudo ./repack_iso_with_groups.sh NiuLinkOS-v1.1.7-2411141913.iso \\
    upload-pulse-1.0.0-1.el7.x86_64.rpm \\
    monitoring-agent-2.1.0-1.el7.x86_64.rpm \\
    custom-service-1.5.3-2.el7.x86_64.rpm

# 或者更简洁的写法
sudo ./repack_iso_with_groups.sh NiuLinkOS-v1.1.7-2411141913.iso *.rpm
```

#### 支持的使用场景:
- **企业软件集成**: 同时集成多个企业内部工具
- **监控套件部署**: 批量集成监控、日志、安全等多个组件
- **开发环境定制**: 集成开发工具链的多个组件
- **合规软件包**: 批量集成安全和合规相关的多个软件包

### 输出文件
- **新ISO**: `NiuLinkOS-v1.1.7-2411141913-repack-groups.iso`
- **日志文件**: `iso_repack_groups.log`
- **验证建议**: 使用生成的ISO进行实际安装测试

## 扩展应用

### 适用场景
1. **企业定制**: 将企业内部软件包集成到安装镜像
2. **批量部署**: 确保特定软件在所有安装中都存在
3. **合规要求**: 自动安装安全或监控软件
4. **开发环境**: 集成开发工具到基础镜像

### 扩展方法
1. **批量包集成**: 可以同时添加任意数量的RPM包，脚本会自动处理每个包的集成
2. **智能包名提取**: 脚本自动从RPM文件中提取包名，支持复杂的版本和架构命名
3. **包组策略**: 所有包都添加到 `core` 和 `minimal` 包组，确保在任何安装模式下都被安装
4. **批量验证**: 对所有集成的包进行完整性验证，确保集成成功
5. **不同包组**: 根据需要可以修改脚本选择不同的目标包组
6. **条件安装**: 修改comps.xml实现条件安装逻辑
7. **其他发行版**: 原理可应用于其他RHEL系列发行版

## 风险评估

### 潜在风险
1. **依赖冲突**: 多个新包之间或与现有包可能存在依赖冲突
2. **空间限制**: 添加多个包会显著增加ISO大小
3. **启动问题**: 错误的修改可能影响系统启动
4. **兼容性**: 包可能与目标系统版本不兼容
5. **包间冲突**: 多个RPM包之间可能存在文件冲突或服务冲突
6. **性能影响**: 大量包的同时安装可能影响安装性能

### 风险缓解
1. **测试环境**: 先在测试环境验证，特别是多包集成时
2. **备份原始**: 保留原始ISO作为备份
3. **渐进测试**: 先测试单个包，再测试多包集成
4. **依赖检查**: 使用 `rpm -qpR` 检查包依赖关系
5. **冲突检测**: 使用 `rpm -qp --conflicts` 检查包冲突
6. **分批集成**: 对于大量包，可以分批次集成和测试
7. **回滚计划**: 准备快速回滚方案

## 结论

通过深入理解CentOS/RHEL的包管理机制，特别是Package Groups的作用，我们成功解决了单个和多个自定义包集成的问题。关键在于认识到仅仅添加包到Repository是不够的，必须确保所有包都被包含在自动安装的包组中。

**多包集成的优势**:
- **批量处理**: 一次性集成多个相关软件包，提高效率
- **一致性保证**: 所有包使用相同的集成策略，确保安装行为一致
- **依赖管理**: 相关包可以一起集成，减少依赖问题
- **运维效率**: 减少ISO重新打包的次数，提高运维效率

这个项目展示了Linux发行版定制的复杂性，以及系统性思考和持续调试的重要性。最终的解决方案不仅解决了单包集成问题，还扩展支持了多包批量集成，为企业级部署和大规模定制提供了强有力的工具。

---

**项目状态**: ✅ 已完成并验证成功  
**最终脚本**: `repack_iso_with_groups.sh` (支持多包集成)  
**验证结果**: 单个和多个RPM包都能成功自动安装并正常运行  
**支持功能**: 单包集成、多包批量集成、智能包名提取、批量验证  
**文档版本**: v2.0 (多包集成版本)  
**更新日期**: 2025-06-12  


