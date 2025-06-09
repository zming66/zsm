import urllib.request
import math
from datetime import datetime
import ipaddress
from netaddr import cidr_merge
import os

def main():
    print("开始生成中国IPv4地址列表...")
    
    # 下载 APNIC 地址分配数据
    url = "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
    print(f"下载APNIC数据: {url}")
    raw_data = urllib.request.urlopen(url).read().decode('utf-8')
    
    # 提取中国 IPv4 地址段
    china_ipv4 = []
    print("处理原始数据...")
    for line in raw_data.splitlines():
        if line.startswith("apnic|CN|ipv4|"):
            parts = line.split('|')
            ip = parts[3]
            count = int(parts[4])
            
            # 计算 CIDR 掩码
            cidr = 32 - int(math.log2(count))
            china_ipv4.append(f"{ip}/{cidr}")
    
    print(f"获取到 {len(china_ipv4)} 个原始IPv4地址段")
    
    # CIDR 合并优化
    print("合并CIDR地址段...")
    networks = [ipaddress.ip_network(cidr) for cidr in china_ipv4]
    merged_cidrs = list(cidr_merge(networks))
    
    print(f"合并后剩余 {len(merged_cidrs)} 个CIDR地址段 (减少 {len(china_ipv4) - len(merged_cidrs)} 个)")
    
    # 生成 RouterOS 脚本
    ros_script = f"""/################################################################
# 中国IPv4地址列表 - 自动生成 ({datetime.utcnow().strftime('%Y-%m-%d')})
# 来源: APNIC | 原始条目: {len(china_ipv4)} | 优化后条目: {len(merged_cidrs)}
################################################################
/ip firewall address-list remove [find where list="CN"]
/ip firewall address-list\n"""
    
    for cidr in merged_cidrs:
        ros_script += f"add address={cidr} list=CN\n"
    
    # 保存文件
    output_file = "china-ipv4.rsc"
    with open(output_file, "w") as f:
        f.write(ros_script)
    
    print(f"生成完成! 输出文件: {output_file}")
    print(f"文件大小: {os.path.getsize(output_file)/1024:.2f} KB")

if __name__ == "__main__":
    main()
