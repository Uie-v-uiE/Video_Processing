#!/usr/bin/env python3
# 用途：r90 的一刀：把 icmp_rx 最坏 setup 路径上的两条借位链换成 17 个触发器
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# r90 的一刀：把 icmp_rx 最坏 setup 路径上的两条借位链换成 17 个触发器。
# 只做事前写好的六处精确替换，任何一处对不上就**不落盘**（规矩：改不动就停，不去猜）。
import sys

PATH = "src/rtl/eth/icmp_rx.v"

EDITS = [
    # 1) 两个新寄存器
    (b"    reg [15:0] icmp_data_length;  //data length register\n",
     b"    reg [15:0] icmp_data_length;  //data length register\n"
     b"    reg [15:0] icmp_len_m1;   //len-1 \xe6\x8f\x90\xe5\x89\x8d\xe5\xaf\x84\xe6\x9e\x81\xef\xbc\x9a\xe6\x8a\x8a\xe5\x87\x8f\xe6\xb3\x95\xe7\xa7\xbb\xe5\x88\xb0\xe4\xb8\x8d\xe5\x9c\xa8\xe6\x9c\x80\xe5\x9d\x8f\xe8\xb7\xaf\xe5\xbe\x84\xe4\xb8\x8a\xe7\x9a\x84\xe4\xb8\x80\xe6\x8b\x8d\n"
     b"    reg        in_data_win;   //\xe6\x95\xb0\xe6\x8d\xae\xe7\xaa\x97\xe6\x97\x97\xe6\xa0\x87\xef\xbc\x8c\xe7\xad\x89\xe4\xbb\xb7\xe4\xba\x8e icmp_rx_cnt < icmp_data_length\n"),
    # 2) 复位清单
    (b"            icmp_data_length   <= 16'd0;\n",
     b"            icmp_data_length   <= 16'd0;\n"
     b"            icmp_len_m1        <= 16'd0;\n"
     b"            in_data_win        <= 1'b0;\n"),
    # 3) 长度落地那一拍顺手把 len-1 也算好（模 2^16 下 total-29 == (total-28)-1）
    (b"                        else if (cnt == 5'd4)\n"
     b"                            //\xe6\x9c\x89\xe6\x95\x88\xe6\x95\xb0\xe6\x8d\xae\xe5\xad\x97\xe8\x8a\x82\xe9\x95\xbf\xe5\xba\xa6\xef\xbc\x8c\xef\xbc\x88IP\xe9\xa6\x96\xe9\x83\xa820\xe4\xb8\xaa\xe5\xad\x97\xe8\x8a\x82\xef\xbc\x8cicmp\xe9\xa6\x96\xe9\x83\xa88\xe4\xb8\xaa\xe5\xad\x97\xe8\x8a\x82\xef\xbc\x8c\xe6\x89\x80\xe4\xbb\xa5\xe5\x87\x8f\xe5\x8e\xbb28\xef\xbc\x89\n"
     b"                            icmp_data_length <= total_length - 16'd28;\n",
     b"                        else if (cnt == 5'd4) begin\n"
     b"                            //\xe6\x9c\x89\xe6\x95\x88\xe6\x95\xb0\xe6\x8d\xae\xe5\xad\x97\xe8\x8a\x82\xe9\x95\xbf\xe5\xba\xa6\xef\xbc\x8c\xef\xbc\x88IP\xe9\xa6\x96\xe9\x83\xa820\xe4\xb8\xaa\xe5\xad\x97\xe8\x8a\x82\xef\xbc\x8cicmp\xe9\xa6\x96\xe9\x83\xa88\xe4\xb8\xaa\xe5\xad\x97\xe8\x8a\x82\xef\xbc\x8c\xe6\x89\x80\xe4\xbb\xa5\xe5\x87\x8f\xe5\x8e\xbb28\xef\xbc\x89\n"
     b"                            icmp_data_length <= total_length - 16'd28;\n"
     b"                            icmp_len_m1      <= total_length - 16'd29;\n"
     b"                        end\n"),
    # 4) 进数据窗那一拍开窗（声明长度 0 就是不开窗，与老的 `cnt < length` 同语义）
    (b"                            if (icmp_type == ECHO_REQUEST) begin\n"
     b"                                skip_en <= 1'b1;\n"
     b"                                cnt     <= 5'd0;\n"
     b"                            end else begin\n",
     b"                            if (icmp_type == ECHO_REQUEST) begin\n"
     b"                                skip_en     <= 1'b1;\n"
     b"                                cnt         <= 5'd0;\n"
     b"                                in_data_win <= (icmp_data_length != 16'd0);\n"
     b"                            end else begin\n"),
    # 5) 数据相：等值比较吃寄存好的 len-1；范围判断吃旗标；最后一个字节把窗关掉
    (b"                        if (icmp_rx_cnt == icmp_data_length - 1) begin\n"
     b"                            icmp_rx_data_d0 <= 8'h00;\n",
     b"                        if (icmp_rx_cnt == icmp_len_m1) begin\n"
     b"                            icmp_rx_data_d0 <= 8'h00;\n"
     b"                            in_data_win     <= 1'b0;\n"),
    (b"                        end else if (icmp_rx_cnt < icmp_data_length) begin\n",
     b"                        end else if (in_data_win) begin\n"),
    # 6) 收完那一处同一个等值
    (b"                        if (icmp_rx_cnt == icmp_data_length - 16'd1) begin\n",
     b"                        if (icmp_rx_cnt == icmp_len_m1) begin\n"),
]


def main():
    raw = open(PATH, "rb").read()
    crlf = b"\r\n" in raw
    data = raw
    if crlf:
        data = data.replace(b"\r\n", b"\n")
    for i, (old, new) in enumerate(EDITS, 1):
        n = data.count(old)
        if n != 1:
            print("REFUSE edit %d matched %d times (want 1) -- nothing written" % (i, n))
            return 2
        data = data.replace(old, new, 1)
    for probe in (b"icmp_len_m1", b"in_data_win"):
        if data.count(probe) < 3:
            print("REFUSE probe %s count too low" % probe)
            return 3
    out = data.replace(b"\n", b"\r\n") if crlf else data
    open(PATH, "wb").write(out)
    print("PATCHED %s (crlf=%s) len_m1=%d in_data_win=%d"
          % (PATH, crlf, out.count(b"icmp_len_m1"), out.count(b"in_data_win")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
