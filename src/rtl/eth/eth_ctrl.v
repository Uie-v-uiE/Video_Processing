//----------------------------------------------------------------------------------------
// File name:           eth_ctrl
// Last modified Date:  2024/11/22
// Last Version:        V1.0
// Descriptions:        eth_ctrl模块
//----------------------------------------------------------------------------------------
// Created by:          riguke
// Created date:        2024/11/22
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module eth_ctrl (
    input            clk,               //时钟
    input            rst_n,             //系统复位信号，低电平有效 
    //ARP相关端口信号                                   
    input            arp_rx_done,       //ARP接收完成信号
    input            arp_rx_type,       //ARP接收类型 0:请求  1:应答
    output reg       arp_tx_en,         //ARP发送使能信号
    output           arp_tx_type,       //ARP发送类型 0:请求  1:应答
    input            arp_tx_done,       //ARP发送完成信号
    input            arp_gmii_tx_en,    //ARP GMII输出数据有效信号 
    input      [7:0] arp_gmii_txd,      //ARP GMII输出数据
    //ICMP相关端口信号
    input            icmp_tx_start_en,  //ICMP开始发送信号
    input            icmp_tx_done,      //ICMP发送完成信号
    input            icmp_gmii_tx_en,   //ICMP GMII输出数据有效信号  
    input      [7:0] icmp_gmii_txd,     //ICMP GMII输出数据 
    //ICMP fifo接口信号
    input            icmp_rec_en,       //ICMP接收的数据使能信号
    input      [7:0] icmp_rec_data,     //ICMP接收的数据
    input            icmp_tx_req,       //ICMP读数据请求信号
    output     [7:0] icmp_tx_data,      //ICMP待发送数据
    //UDP相关端口信号
    input            udp_tx_start_en,   //UDP开始发送信号
    input            udp_tx_done,       //UDP发送完成信号
    input            udp_gmii_tx_en,    //UDP GMII输出数据有效信号  
    input      [7:0] udp_gmii_txd,      //UDP GMII输出数据   
    //UDP fifo接口信号
    input      [7:0] udp_rec_data,      //UDP接收的数据
    input            udp_rec_en,        //UDP接收的数据使能信号 
    input            udp_tx_req,        //UDP读数据请求信号
    output     [7:0] udp_tx_data,       //UDP待发送数据
    //fifo接口信号
    input      [7:0] tx_data,           //待发送的数据
    output           tx_req,            //读数据请求信号 
    output reg       rec_en,            //接收的数据使能信号
    output reg [7:0] rec_data,          //接收的数据
    //GMII发送引脚                  	   
    output reg       gmii_tx_en,        //GMII输出数据有效信号 
    output reg [7:0] gmii_txd           //GMII输出数据 
);

    //reg define
    reg [1:0] protocol_sw;  //协议切换信号
    reg       icmp_tx_busy;  //ICMP正在发送数据标志信号	
    reg       udp_tx_busy;  //UDP正在发送数据标志信号
    reg       arp_rx_flag;  //接收到ARP请求信号的标志
    reg       icmp_tx_req_d0;  //ICMP读数据请求信号寄存器
    reg       udp_tx_req_d0;  //UDP读数据请求信号寄存器

    //*****************************************************
    //**                    main code
    //*****************************************************

    assign arp_tx_type  = 1'b1;  //ARP发送类型固定为ARP应答    				
    assign tx_req       = udp_tx_req ? 1'b1 : icmp_tx_req;  //读数据请求信号选择
    assign icmp_tx_data = icmp_tx_req_d0 ? tx_data : 8'd0;  //ICMP待发送数据选择
    assign udp_tx_data  = udp_tx_req_d0 ? tx_data : 8'd0;  //UDP待发送数据选择

    //ICMP读数据请求信号和UDP读数据请求信号寄存一拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            icmp_tx_req_d0 <= 1'd0;
            udp_tx_req_d0  <= 1'd0;
        end else begin
            icmp_tx_req_d0 <= icmp_tx_req;
            udp_tx_req_d0  <= udp_tx_req;
        end
    end

    //接收数据使能信号与接收数据的判断
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rec_en   <= 1'd0;
            rec_data <= 1'd0;
        end else if (icmp_rec_en) begin
            rec_en   <= icmp_rec_en;
            rec_data <= icmp_rec_data;
        end else if (udp_rec_en) begin
            rec_en   <= udp_rec_en;
            rec_data <= udp_rec_data;
        end else begin
            rec_en   <= 1'd0;
            rec_data <= rec_data;
        end
    end

    //协议的切换
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gmii_tx_en <= 1'd0;
            gmii_txd   <= 8'd0;
        end else begin
            case (protocol_sw)
                2'b00: begin
                    gmii_tx_en <= arp_gmii_tx_en;
                    gmii_txd   <= arp_gmii_txd;
                end
                2'b01: begin
                    gmii_tx_en <= udp_gmii_tx_en;
                    gmii_txd   <= udp_gmii_txd;
                end
                2'b10: begin
                    gmii_tx_en <= icmp_gmii_tx_en;
                    gmii_txd   <= icmp_gmii_txd;
                end
                default: ;
            endcase
        end
    end

    //控制ICMP发送忙信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            icmp_tx_busy <= 1'b0;
        end else if (icmp_tx_start_en) icmp_tx_busy <= 1'b1;
        else if (icmp_tx_done) icmp_tx_busy <= 1'b0;
        
    end


    //控制UDP发送忙信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) udp_tx_busy <= 1'b0;
        else if (udp_tx_start_en) udp_tx_busy <= 1'b1;
        else if (udp_tx_done) udp_tx_busy <= 1'b0;
        
    end

    //控制接收到ARP请求信号的标志
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) arp_rx_flag <= 1'b0;
        else if (arp_rx_done && (arp_rx_type == 1'b0)) arp_rx_flag <= 1'b1;
        else arp_rx_flag <= 1'b0;
    end

    // 收到 ARP 请求后先"记账"，等介质真空闲才发应答（V7.9 / ISSUES #28）。
    // 原来这里只有一拍宽的 arp_rx_flag，把下面那条 OR 改成 && 之后，请求会在
    // "另一路正在发"的那一拍被**丢掉**（PC 要等 ARP 超时重发），所以修 bug 不能只改符号。
    //
    // 记账和兑现必须放在**同一个 always**里：第一版我把 arp_pend 写在单独的块里、
    // 用 `else if (arp_tx_en)` 清账，结果读到的是上一拍的 arp_tx_en（非阻塞赋值），
    // 于是 arp_tx_en 连高两拍、ARP 帧第 0 字节被重发一次（台架数到 13 个字节而不是 12）。
    reg arp_pend;
    //控制protocol_sw和arp_tx_en信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            protocol_sw <= 2'b0;
            arp_tx_en   <= 1'b0;
            arp_pend    <= 1'b0;
        end else begin
            arp_tx_en <= 1'b0;
            if (udp_tx_start_en) begin
                protocol_sw <= 2'b01;
            end else if (icmp_tx_start_en) begin
                protocol_sw <= 2'b10;
            end else if (arp_pend && (udp_tx_busy == 1'b0) && (icmp_tx_busy == 1'b0)) begin
                // 原文是两个独立 busy 用 `||` 连起来（"任一空闲"）⇒ 会在**帧中间**把 mux
                // 切给 ARP，正在发的那帧剩下的字节就地作废。要的是"全部空闲"。
                protocol_sw <= 2'b0;
                arp_tx_en   <= 1'b1;
                arp_pend    <= 1'b0;   // 与授权同拍清账 ⇒ arp_tx_en 恰好一拍宽
            end
            // 记账放在最后：同拍"兑现旧账 + 又来新请求"时，新请求不会被这次授权吃掉。
            if (arp_rx_flag) arp_pend <= 1'b1;
        end
    end

endmodule
