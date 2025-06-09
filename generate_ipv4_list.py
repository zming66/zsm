import urllib.request
import math
from datetime import datetime
import ipaddress
from netaddr import cidr_merge

def main():
    # 下载 APNIC 地址分配数据
    url = "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest"
    raw_data = urllib.request.urlopen(url).read().decode('utf-8')
    
    # 提取中国 IPv4 地址段并转换为 CIDR
    china_ipv4 = []
    for line in raw_data.splitlines():
        if line.startswith("apnic|CN|ipv4|"):
            parts = line.split('|')
            ip = parts[3]
            count = int(parts[4])
            
            # 计算 CIDR 掩码
            cidr = 32 - int(math.log2(count))
            china_ipv4.append(f"{ip}/{cidr}")
    
    # CIDR 合并优化 (减少条目数量)
    merged_cidrs = list(cidr_merge([ipaddress.ip_network(cidr) for cidr in china_ipv4]))
    
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
    with open("china-ipv4.rsc", "w") as f:
        f.write(ros_script)
    
    print(f"生成完成! 原始条目: {len(china_ipv4)} 优化后: {len(merged_cidrs)}")

if __name__ == "__main__":
    main()
