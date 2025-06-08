# 中国IP地址列表自动更新脚本 v2.1
# 修正语法错误，确保命令完整性
# 功能：自动下载并更新中国IPv4和IPv6地址列表
# 支持 RouterOS v6.45+ (建议 v7.x 以上版本)
# 执行时间：约 3-5 分钟（取决于设备性能）

# ================ 配置区域 ================
:local listNameV4 "CN"          # IPv4地址列表名称
:local listNameV6 "CN"         # IPv6地址列表名称（修改为不同名称，避免混淆）
:local ipv4Source "https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
:local ipv6Source "https://raw.githubusercontent.com/ChanthMiao/China-IPv6-List/release/cn6.txt"
:local maxEntriesPerRun 200     # 每次处理的最大条目数（避免内存不足）
# =========================================

# 主函数
:local updateChinaIPList do={
    :local startTime [/system clock get time]
    :log info "开始更新中国IP地址列表..."
    
    # 创建临时文件
    :local ipv4File ("china_ipv4_" . [/system identity get name] . ".tmp")
    :local ipv6File ("china_ipv6_" . [/system identity get name] . ".tmp")
    
    # 下载IPv4列表
    :log info "下载中国IPv4地址列表..."
    /tool fetch url=$ipv4Source mode=https dst-path=$ipv4File
    
    # 下载IPv6列表
    :log info "下载中国IPv6地址列表..."
    /tool fetch url=$ipv6Source mode=https dst-path=$ipv6File
    
    # 处理IPv4地址
    :log info "处理IPv4地址条目..."
    /ip firewall address-list remove [find list=$listNameV4]
    :delay 1s
    :local ipv4List [/file find name=$ipv4File]
    :if ([:len $ipv4List] > 0) do={
        :local ipv4Content [/file get $ipv4List contents]
        :local ipv4Array [:toarray $ipv4Content]
        :local ipv4Count 0
        
        :foreach entry in=$ipv4Array do={
            :if ([:len $entry] > 7 && [:pick $entry 0 1] != "#") do={
                /ip firewall address-list add address=$entry list=$listNameV4
                :set ipv4Count ($ipv4Count + 1)
                
                # 分批处理避免内存溢出
                :if ($ipv4Count % $maxEntriesPerRun = 0) do={
                    :log info ("已处理 " . $ipv4Count . " 条IPv4地址...")
                    :delay 0.1s
                }
            }
        }
        :log info ("IPv4地址列表更新完成，共添加 " . $ipv4Count . " 条记录")
        /file remove $ipv4List
    } else={
        :log warning "IPv4列表文件不存在，下载可能失败！"
    }
    
    # 处理IPv6地址 (RouterOS v7+ required)
    :log info "处理IPv6地址条目..."
    /ipv6 firewall address-list remove [find list=$listNameV6]
    :delay 1s
    :local ipv6List [/file find name=$ipv6File]
    :if ([:len $ipv6List] > 0) do={
        :local ipv6Content [/file get $ipv6List contents]
        :local ipv6Array [:toarray $ipv6Content]
        :local ipv6Count 0
        
        :foreach entry in=$ipv6Array do={
            :if ([:len $entry] > 7 && [:pick $entry 0 1] != "#") do={
                /ipv6 firewall address-list add address=$entry list=$listNameV6
                :set ipv6Count ($ipv6Count + 1)
                
                # 分批处理避免内存溢出
                :if ($ipv6Count % $maxEntriesPerRun = 0) do={
                    :log info ("已处理 " . $ipv6Count . " 条IPv6地址...")
                    :delay 0.1s
                }
            }
        }
        :log info ("IPv6地址列表更新完成，共添加 " . $ipv6Count . " 条记录")
        /file remove $ipv6List
    } else={
        :log warning "IPv6列表文件不存在，下载可能失败！"
    }
    
    # 计算执行时间
    :local endTime [/system clock get time]
    :local duration [:pick $endTime 0 2]-[:pick $startTime 0 2]."h ".[:pick $endTime 3 5]-[:pick $startTime 3 5]."m ".[:pick $endTime 6 8]-[:pick $startTime 6 8]."s"
    
    :log info ("中国IP列表更新完成! IPv4: " . $ipv4Count . "条, IPv6: " . $ipv6Count . "条")
    :log info ("执行时间: " . $duration)
}

# 执行更新
:log info "===== 中国IP地址列表更新开始 ====="
updateChinaIPList
:log info "===== 更新过程已完成 ====="
