# S7 · 板级以太网与串口（可复用）

## 适用场景
RTL8211、双网卡 PC、第三方串口助手。

## 使用方法
- RTL8211 自协商失败：BSP `CONFIG_LINKSPEED1000`  
- PC 双网卡：`socket.bind(("192.168.1.100", 0))`  
- 串口：115200 8N1，发送 **CR+LF**  
- 双网口板：PS ETH 与 PL ETH 物理分离，推流选对口  

## 已验证效果
- ISSUES#4/#6/#7  
- 用户手册：eth0=PS，eth1=PL  

## 失效条件
- 线材/变压器问题  
- 防火墙或 IP 不同网段  
- Platform 重编冲掉 lwipopts（若仍用 PS 网口）
