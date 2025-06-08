# 创建自动更新脚本
/system script add name="Update_CN_IPs" source={
    # 删除旧地址列表
    /ip firewall address-list remove [find where list~"CN_IP"];
    /ipv6 firewall address-list remove [find where list~"CN_IP"];
    
    # 下载中国IPv4列表 (含10.10.10.0/24)
    /tool fetch url="https://api.ispip.com/all_cn_cidr.txt" dst-path="cn_ipv4.txt";
    /file set "cn_ipv4.txt" contents=("10.10.10.0/24\\n" . [get "cn_ipv4.txt" contents]);
    
    # 导入IPv4地址列表
    :foreach line in=[/file get cn_ipv4.txt contents] do={
        /ip firewall address-list add list="CN_IPv4" address=$line;
    }
    
    # 下载中国IPv6列表
    /tool fetch url="https://api.ispip.com/all_cn_ipv6_cidr.txt" dst-path="cn_ipv6.txt";
    
    # 导入IPv6地址列表
    :foreach line in=[/file get cn_ipv6.txt contents] do={
        /ipv6 firewall address-list add list="CN_IPv6" address=$line;
    }
    
    # 清理临时文件
    /file remove "cn_ipv4.txt";
    /file remove "cn_ipv6.txt";
    
    # 添加日志标记
    :log info message="中国IP列表更新完成";
}

# 添加定时任务（每天3点自动更新）
/system scheduler add name="Daily_CN_IP_Update" interval=1d start-time=03:00:00 on-event="/system script run Update_CN_IPs";

# 首次立即执行
/system script run Update_CN_IPs;
