#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

#运行目录
MODEM_RUNDIR="/var/run/modem"

#导入组件工具
source "${SCRIPT_DIR}/modem_debug.sh"

#GobiNet拨号
# $1:AT串口
# $2:制造商
# $3:连接定义
gobinet_dial()
{
    local at_port="$1"
    local manufacturer="$2"
    local define_connect="$3"

    #激活
    local at_command="AT+CGACT=1,${define_connect}"
    #打印日志
    dial_log "${at_command}" "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"

    at "${at_port}" "${at_command}"

    #拨号
    local at_command
    if [ "$manufacturer" = "quectel" ]; then
        at_command='ATI'
    elif [ "$manufacturer" = "fibocom" ]; then
        at_command='AT$QCRMCALL=1,3'
    else
        at_command='ATI'
    fi

    #打印日志
    dial_log "${at_command}" "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"

    at "${at_port}" "${at_command}"
}

#ECM拨号
# $1:AT串口
# $2:制造商
# $3:连接定义
ecm_dial()
{
    local at_port="$1"
    local manufacturer="$2"
    local define_connect="$3"

    #激活
    local at_command="AT+CGACT=1,${define_connect}"
    #打印日志
    dial_log "${at_command}" "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"

    at "${at_port}" "${at_command}"

    sleep 2s

    #拨号
    local at_command
    if [ "$manufacturer" = "quectel" ]; then
        at_command="AT+QNETDEVCTL=${define_connect},3,1"
    elif [ "$manufacturer" = "fibocom" ]; then
        at_command="AT+GTRNDIS=1,${define_connect}"
    else
        at_command='ATI'
    fi

    #打印日志
    dial_log "${at_command}" "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"

    at "${at_port}" "${at_command}"
}

#RNDIS拨号
# $1:AT串口
# $2:制造商
# $3:平台
# $4:连接定义
# $5:接口名称
rndis_dial()
{
    local at_port="$1"
    local manufacturer="$2"
    local platform="$3"
    local define_connect="$4"
    local interface_name="$5"

    #手动设置IP（广和通FM350-GL）
    if [ "$manufacturer" = "fibocom" ] && [ "$platform" = "mediatek" ]; then

        #激活并拨号
        at_command="AT+CGACT=1,${define_connect}"
        #打印日志
        dial_log "${at_command}" "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"

        at "${at_port}" "${at_command}"

        #获取IPv4地址
        at_command="AT+CGPADDR=${define_connect}"
        local ipv4=$(at ${at_port} ${at_command} | grep "+CGPADDR: " | awk -F',' '{print $2}' | sed 's/"//g')

        #设置静态地址
        local ipv4_config=$(uci -q get network.${interface_name}.ipaddr)
        if [ "$ipv4_config" != "$ipv4" ]; then
            uci set network.${interface_name}.proto='static'
            uci set network.${interface_name}.ipaddr="$ipv4"
            uci set network.${interface_name}.netmask='255.255.255.0'
            uci set network.${interface_name}.gateway="${ipv4%.*}.1"
            uci commit network
            service network reload
        fi
    else
        #拨号
        ecm_dial "${at_port}" "${manufacturer}"
    fi
}

#Modem Manager拨号
# $1:接口名称
# $2:连接定义
modemmanager_dial()
{
    local interface_name="$1"
    local define_connect="$2"

    #激活
    local at_command="AT+CGACT=1,${define_connect}"
    #打印日志
    dial_log "${at_command}" "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"
    at "${at_port}" "${at_command}"

    #启动网络接口
    ifup "${interface_name}";
}

#检查模组网络连接
# $1:配置ID
# $2:模组序号
# $3:拨号模式
modem_network_task()
{
    local config_id="$1"
    local modem_no="$2"
    local mode="$3"

    #获取AT串口，制造商，平台，连接定义，接口名称
    local at_port=$(uci -q get modem.modem${modem_no}.at_port)
	local manufacturer=$(uci -q get modem.modem${modem_no}.manufacturer)
	local platform=$(uci -q get modem.modem${modem_no}.platform)
    local define_connect=$(uci -q get modem.modem${modem_no}.define_connect)
    local interface_name="wwan_5g_${modem_no}"

    #重载配置（解决AT命令发不出去的问题）
    # service modem reload

    #IPv4地址缓存
    local ipv4_cache

    while true; do
        #全局
        local enable=$(uci -q get modem.@global[0].enable)
        if [ "$enable" != "1" ]; then
            break
        fi
        #单个模组
        enable=$(uci -q get modem.$config_id.enable)
        if [ "$enable" != "1" ]; then
            break
        fi

        #网络连接检查
        local at_command="AT+CGPADDR=${define_connect}"
        local ipv4=$(at ${at_port} ${at_command} | grep "+CGPADDR: " | awk -F'"' '{print $2}')

        if [ -z "$ipv4" ] || [[ "$ipv4" = *"0.0.0.0"* ]] || [ "$ipv4" != "$ipv4_cache" ]; then

            if [ -z "$ipv4" ]; then
                #输出日志
                echo "$(date +"%Y-%m-%d %H:%M:%S") redefine connect" >> "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"
                service network modem
                sleep 1s
            else
                #缓存当前IP
                ipv4_cache="${ipv4}"
                #输出日志
                echo "$(date +"%Y-%m-%d %H:%M:%S") Modem${modem_no} current IP : ${ipv4}" >> "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"
            fi

            #输出日志
            echo "$(date +"%Y-%m-%d %H:%M:%S") check or redial" >> "${MODEM_RUNDIR}/modem${modem_no}_dial.cache"
            
            case "$mode" in
                "gobinet") gobinet_dial "${at_port}" "${manufacturer}" "${define_connect}" ;;
                "ecm") ecm_dial "${at_port}" "${manufacturer}" "${define_connect}" ;;
                "rndis") rndis_dial "${at_port}" "${manufacturer}" "${platform}" "${define_connect}" "${interface_name}" ;;
                "modemmanager") modemmanager_dial "${interface_name}" "${define_connect}" ;;
                *) ecm_dial "${at_port}" "${manufacturer}" "${define_connect}" ;;
            esac
        fi

        sleep 5s
    done
}

modem_network_task "$1" "$2" "$3"