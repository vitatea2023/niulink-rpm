# CentOS/RHEL ISO 自定义RPM包集成工具

## 项目概述

本项目提供了一个通用的解决方案，用于将一个或多个自定义RPM包集成到 CentOS/RHEL 系列 ISO 镜像中，确保这些包在系统安装过程中被自动安装。该工具支持批量集成多个RPM包，所有包都会被添加到默认安装的包组中，确保在全自动安装过程中被强制安装。

**核心脚本**: `repack_iso_with_groups.sh`

## 主要特性

- ✅ **单包集成**: 支持集成单个RPM包
- ✅ **多包批量集成**: 支持同时集成多个RPM包
- ✅ **智能包名提取**: 自动从RPM文件中提取包名
- ✅ **强制安装保证**: 包被添加到mandatory包组，确保自动安装
- ✅ **UEFI兼容**: 修复UEFI启动问题，支持Secure Boot
- ✅ **双启动支持**: 同时支持UEFI和Legacy BIOS启动
- ✅ **USB启动兼容**: 修复USB物理设备启动问题，支持BalenaEtcher等工具
- ✅ **批量验证**: 自动验证所有包的集成状态
- ✅ **详细日志**: 完整的操作日志记录

## 快速开始

### 环境要求

- Debian 12 (Bookworm) 或兼容系统
- Root权限
- 足够的磁盘空间（至少4GB空闲空间）

### 安装依赖

```bash
sudo apt update
sudo apt install -y xorriso squashfs-tools createrepo-c
```

### 基本使用

#### 单个RPM包集成
```bash
sudo ./repack_iso_with_groups.sh original.iso custom-package.rpm
```

#### 多个RPM包集成
```bash
# 方式1: 逐个指定
sudo ./repack_iso_with_groups.sh original.iso \\
    package1.rpm \\
    package2.rpm \\
    package3.rpm

# 方式2: 通配符批量
sudo ./repack_iso_with_groups.sh original.iso *.rpm

# 方式3: 混合方式
sudo ./repack_iso_with_groups.sh original.iso \\
    essential-package.rpm \\
    monitoring-*.rpm \\
    security-tools.rpm
```

### 使用示例

#### 企业软件套件集成
```bash
sudo ./repack_iso_with_groups.sh CentOS-7-x86_64-DVD-2009.iso \\
    company-agent-1.2.0-1.el7.x86_64.rpm \\
    monitoring-client-2.1.5-1.el7.x86_64.rpm \\
    security-scanner-1.8.3-2.el7.x86_64.rpm
```

#### 开发环境定制
```bash
sudo ./repack_iso_with_groups.sh RHEL-8.5-x86_64-dvd.iso \\
    docker-ce-20.10.12-3.el8.x86_64.rpm \\
    kubectl-1.23.0-0.x86_64.rpm \\
    development-tools-*.rpm
```

## 工作原理

### 技术核心

1. **Repository双重更新**: 同时更新根级repository和Packages repository
2. **包组集成**: 将自定义包添加到`core`和`minimal`包组
3. **强制安装**: 使用`mandatory`类型确保包被自动安装
4. **UEFI修复**: 修复CentOS/RHEL的UEFI启动问题
5. **USB启动修复**: 添加isohybrid MBR分区表支持，确保USB物理设备启动兼容

### 关键步骤

1. 提取ISO内容
2. 复制RPM包到Packages目录
3. 更新Packages repository元数据
4. 提取包名并修改comps.xml
5. 更新根级repository包含包组信息
6. 应用UEFI启动修复
7. 重新打包ISO（集成USB启动兼容性支持）

### 包组策略

所有自定义包会被添加到以下包组：
- **core组**: `default=true`, `type=mandatory` - 确保基础安装包含
- **minimal环境**: `type=mandatory` - 确保最小安装也包含

## 适用场景

### 企业级部署
- **标准化环境**: 确保所有系统都安装企业必需软件
- **合规要求**: 自动安装安全和审计软件
- **监控部署**: 批量集成监控、日志、APM等组件

### 开发环境
- **工具链集成**: 预装开发工具和运行时环境
- **容器化环境**: 集成Docker、Kubernetes等容器工具
- **CI/CD工具**: 预装构建和部署工具

### 安全加固
- **安全工具**: 集成防病毒、入侵检测等安全软件
- **加密工具**: 预装磁盘加密和证书管理工具
- **审计软件**: 集成日志审计和合规检查工具

## 输出结果

脚本执行成功后会生成：
- **新ISO文件**: `原始ISO名称-repack-groups.iso`
- **详细日志**: `iso_repack_groups.log`
- **集成报告**: 显示所有集成的包和验证状态

### 预期效果

使用生成的ISO安装系统时：
- ✅ 所有集成的RPM包会被自动安装
- ✅ 支持UEFI和Legacy BIOS双重启动
- ✅ 支持USB物理设备启动（BalenaEtcher兼容）
- ✅ 无需手动干预，全自动安装
- ✅ 包服务会在安装后自动启动

## 高级使用

### 包依赖检查

在集成前建议检查包依赖：
```bash
# 查看包依赖
rpm -qpR package.rpm

# 查看包冲突
rpm -qp --conflicts package.rpm

# 查看包信息
rpm -qpi package.rpm
```

### 分批集成策略

对于大量包，建议分批集成：
```bash
# 第一批：基础包
sudo ./repack_iso_with_groups.sh original.iso base-*.rpm

# 第二批：在第一批基础上继续
sudo ./repack_iso_with_groups.sh output-from-first-batch.iso additional-*.rpm
```

### 自定义包组

如需修改目标包组，可以编辑脚本中的包组逻辑：
```bash
# 修改脚本中的这些行来改变目标包组
sed -i '/<id>core<\/id>/,/<\/packagelist>/ {
    /<\/packagelist>/ i\      <packagereq type="mandatory">'"$pkg_name"'</packagereq>
}' "$COMPS_FILE"
```

## 故障排除

### 常见问题

1. **包没有被安装**
   - 检查包是否在包组中：`grep package-name comps.xml`
   - 检查包是否在repository中：`zcat repodata/*primary.xml.gz | grep package-name`

2. **ISO启动失败**
   - 确保原始ISO完整且未损坏
   - 检查工作目录权限和磁盘空间

3. **USB启动"分区表未找到"错误**
   - 使用`fdisk -l 镜像.iso`检查分区表结构
   - 确保镜像包含isohybrid MBR分区表

4. **依赖冲突**
   - 使用`rpm -qpR`检查包依赖
   - 确保所有依赖包已存在于原始ISO中

### 日志分析

详细日志记录在`iso_repack_groups.log`中：
```bash
# 查看错误信息
grep ERROR iso_repack_groups.log

# 查看成功状态
grep SUCCESS iso_repack_groups.log

# 查看包集成状态
grep "package.*added" iso_repack_groups.log
```

## 风险评估与缓解

### 潜在风险
- **依赖冲突**: 多个包之间或与现有包的依赖冲突
- **空间限制**: 大量包会显著增加ISO大小
- **兼容性**: 包可能与目标系统版本不兼容
- **性能影响**: 大量包的安装可能影响部署性能

### 缓解策略
- **测试环境**: 先在测试环境验证集成效果
- **依赖检查**: 使用RPM工具检查包依赖和冲突
- **分批测试**: 先测试单个包，再测试批量集成
- **回滚准备**: 保留原始ISO作为备份

## 兼容性

### 支持的发行版
- CentOS 7.x
- RHEL 7.x, 8.x
- Rocky Linux
- AlmaLinux
- 其他兼容的EL系列发行版

### 支持的架构
- x86_64 (主要测试架构)
- 理论上支持其他架构，但需要相应的RPM包

## 贡献

欢迎提交Issue和Pull Request来改进这个工具。

### 开发指南
1. Fork本仓库
2. 创建特性分支
3. 提交您的改动
4. 创建Pull Request

## 许可证

本项目采用开源许可证，具体请查看LICENSE文件。

## 更新日志

### v2.0 (2025-06-12)
- ✨ 新增多RPM包批量集成支持
- 🔧 智能包名提取和验证
- 📝 完善的文档和使用示例
- 🛡️ 增强的错误处理和日志记录

### v1.0 (2025-06-11)
- 🎉 初始版本发布
- ✅ 单RPM包集成功能
- 🔧 UEFI启动修复
- 📋 基础文档和技术报告

---

**项目状态**: ✅ 生产就绪  
**维护状态**: 🔄 积极维护  
**文档版本**: v2.0  
**最后更新**: 2025-06-12