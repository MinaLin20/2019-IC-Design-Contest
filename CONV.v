`timescale 1ns/10ps

module  CONV(
        input           clk,
        input           reset,
        output          reg busy,       
        input           ready,  
                        
        output          reg [11:0] iaddr,
        input           signed[19:0] idata,   
        
        output          reg cwr,
        output          reg [11:0] caddr_wr,
        output          reg signed[19:0] cdata_wr,
        
        output          reg crd,
        output          reg [11:0] caddr_rd,
        input           signed[19:0] cdata_rd,
        
        output          reg [3:0] csel
        );
        reg [3:0] state, next_state;

    parameter IDLE = 4'd0, CONV = 4'd1,RESULT0 = 4'd2,L0_MEM0 = 4'd3,L0_MEM1 = 4'd4,POOLING_k0 = 4'd5,L1_MEM0 = 4'd6,POOLING_k1 = 4'd7
                ,L1_MEM1 = 4'd8,FLAT_RD= 4'd9,FLAT_WR=4'd10,FINISH = 4'd11;
    reg [5:0] conv_i;
    reg [5:0] conv_j;
    reg [3:0] conv_count;
    reg [2:0] pooling_count;
    reg signed [19:0] conv_image;
    reg signed [19:0] conv_multi0;
    reg signed [19:0] conv_multi1;
    reg signed [39:0] temp_conv_out0;//kernal0 output indep
    reg signed [39:0] temp_conv_out1;//kernal1 output indep
    reg signed [39:0] conv_sum0;//kernal0 sum
    reg signed [39:0] conv_sum1;//kernal1 sum
    
    localparam signed [39:0] BIAS0 = 40'sh0013100000; //  +0.07446326
    localparam signed [39:0] BIAS1 = 40'shFF72950000; //  -0.55241907
    reg [4:0] pool_i, pool_j;
    reg signed [19:0] pool_max;
    wire signed[19:0] conv_result0;
    wire signed[19:0] conv_result1;   
    //FLAT
    reg [11:0] read_ptr;   //  (0..2047)
    reg signed [19:0] flat_data;  
    reg [12:0] flat_cnt;

    //setting state
    always@(posedge clk or posedge reset)
    begin
        if(reset)
            state <= IDLE;
        else
            state <= next_state;
    end             
    //setting FSM
    always@(*)begin    
            case(state)
            IDLE:next_state = CONV;
            CONV:begin
                    if(conv_count == 10)
                        next_state = RESULT0;
                    else
                        next_state = CONV;
                end
            RESULT0:next_state = L0_MEM0;
            L0_MEM0:next_state = L0_MEM1;
            L0_MEM1:begin
                    if(conv_i == 0 && conv_j == 0)
                        next_state = POOLING_k0;
                    else
                        next_state = CONV;
                end
            POOLING_k0:begin if(pooling_count ==5 )
                        next_state = L1_MEM0;
                    else
                        next_state = POOLING_k0;
                end
            L1_MEM0:next_state = POOLING_k1;    
            POOLING_k1:begin if(pooling_count == 5)
                        next_state = L1_MEM1;
                    else
                        next_state = POOLING_k1;
                end
            L1_MEM1:begin
                    if(conv_i == 0 && conv_j == 0)
                        next_state = FLAT_RD;
                    else
                        next_state = POOLING_k0;
                end
           FLAT_RD: begin
                next_state = FLAT_WR;  //                              
                end

            FLAT_WR: begin
                    if (flat_cnt == 12'd2048)
                        next_state = FINISH;
                    else
                        next_state = FLAT_RD;  //                                    
        end

            FINISH:next_state = FINISH;
            default:next_state = IDLE;
        endcase
    end


    //setting busy duration
    always@(posedge clk or posedge reset)
    begin
        if(reset) busy <= 1'd0;
        else if(ready) 
            busy <= 1'd1;
        else if(state == FINISH)
            busy <= 1'd0;
    end

    //setting conv_count
    always@(posedge clk or posedge reset)
    begin
        if(reset) conv_count <= 4'd0;
        else if(next_state == CONV) conv_count <= conv_count + 4'd1;
        else if(next_state == RESULT0) conv_count <=conv_count + 4'd1;
        else if(next_state == L0_MEM0) conv_count <=conv_count + 4'd1;
        else if(next_state == L0_MEM1) conv_count <= 4'd0;
    end
    
    //setting pooling_count
    always@(posedge clk or posedge reset)
    begin
        if(reset) pooling_count <= 3'd0;
        else if(next_state == POOLING_k0) pooling_count <= pooling_count + 3'd1;
        else if(next_state == POOLING_k1) pooling_count <= pooling_count + 3'd1;
        else if(next_state == L1_MEM0) pooling_count <= 3'd0;
        else if(next_state == L1_MEM1) pooling_count <= 3'd0;
    end

    // setting figure coordinate
    always@(posedge clk or posedge reset)
    begin
        if(reset)
        begin
            conv_i <= 6'd0;
            conv_j <= 6'd0;
        end
        else if (next_state==L0_MEM1)
        begin
            conv_i <= (conv_j == 63)? conv_i+1:conv_i;
            conv_j <= conv_j + 1;
        end
        else if(next_state==L1_MEM1)
        begin
            conv_j <= conv_j + 2;
            conv_i <= (conv_j== 62)?conv_i+2:conv_i;
        end

    end
    

    // setting iaddr
    always@(posedge clk or posedge reset)
    begin
        if(reset)
            iaddr <= 12'd0;    
        //conv
        else if(next_state == CONV)
        case(conv_count)
            0: iaddr <= {conv_i - 6'd1,conv_j - 6'd1};
            1: iaddr <= {conv_i - 6'd1 , conv_j };
            2: iaddr <= {conv_i - 6'd1 , conv_j + 6'd1};
            3: iaddr <= {conv_i , conv_j - 6'd1};
            4: iaddr <= {conv_i , conv_j };
            5: iaddr <= {conv_i , conv_j + 6'd1};
            6: iaddr <= {conv_i + 6'd1,conv_j - 6'd1};
            7: iaddr <= {conv_i + 6'd1 , conv_j };
            8: iaddr <= {conv_i + 6'd1 , conv_j + 6'd1};
            default: iaddr <= 12'd0;
        endcase
        //pooling
        else if(next_state == POOLING_k0||POOLING_k1)
        case(pooling_count)
            0: iaddr <= {conv_i ,conv_j };
            1: iaddr <= {conv_i , conv_j + 6'd1};
            2: iaddr <= {conv_i + 6'd1, conv_j };
            3: iaddr <= {conv_i + 6'd1, conv_j + 6'd1};
            default: iaddr <= 12'd0;
        endcase
    end

   //conv
    always @(posedge clk or posedge reset)
    begin
        if(reset) conv_image <= 12'd0;    
        else begin
        case (conv_count)
            1: conv_image <= ((conv_i == 0)  || (conv_j == 0))  ? 20'sd0 : idata; 
            2: conv_image <= (conv_i == 0)                      ? 20'sd0 : idata; 
            3: conv_image <= ((conv_i == 0)  || (conv_j == 63)) ? 20'sd0 : idata; 
            4: conv_image <= ((conv_j == 0))                    ? 20'sd0 : idata; 
            5: conv_image <= idata;  
            6: conv_image <= ((conv_j == 63))                   ? 20'sd0 : idata; 
            7: conv_image <= ((conv_i == 63) || (conv_j == 0))  ? 20'sd0 : idata; 
            8: conv_image <= ((conv_i == 63))                   ? 20'sd0 : idata; 
            9: conv_image <= ((conv_i == 63) || (conv_j == 63)) ? 20'sd0 : idata; 
            default:conv_image <= 20'sd0;
        endcase
        end
    end
    // ---------- Kernel 0 ----------
    always@(posedge clk or posedge reset)
    begin
        if(reset) conv_multi0 <= 20'd0;    
        else begin
        case(conv_count)
            1:conv_multi0 <= 20'sh0A89E; //0.6586609
            2:conv_multi0 <= 20'sh092D5; // +0.573572
            3:conv_multi0 <= 20'sh06D43; // +0.42681
            4:conv_multi0 <= 20'sh01004; // +0.0625617
            5:conv_multi0 <= 20'shF8F71; // -0.439696
            6:conv_multi0 <= 20'shF6E54; // -0.569037
            7:conv_multi0 <= 20'shFA6D7; // -0.34829
            8:conv_multi0 <= 20'shFC834; // -0.217964
            9:conv_multi0 <= 20'shFAC19; // -0.327755
            default: conv_multi0 <= 20'sd0;
        endcase
        end
    end
    // ---------- Kernel 1 ----------
    always@(posedge clk or posedge reset)
    begin
        if(reset) conv_multi1 <= 20'd0;    
        else begin
  
        case(conv_count)
            1:conv_multi1 <= 20'shFDB55; //  -0.143247
            2:conv_multi1 <= 20'sh02992; //  +0.162391
            3:conv_multi1 <= 20'shFC994; //  -0.212595
            4:conv_multi1 <= 20'sh050FD; //  +0.31637
            5:conv_multi1 <= 20'sh02F20; //  +0.184082
            6:conv_multi1 <= 20'sh0202D; //  +0.125697
            7:conv_multi1 <= 20'sh03BD7; //  +0.23376
            8:conv_multi1 <= 20'shFD369; //  -0.174190
            9:conv_multi1 <= 20'sh05E68; //  +0.368789
            default: conv_multi1 <= 20'sd0;
        endcase
        end
    end
    //conv_image*conv_multi
    always@(*)
    begin
        temp_conv_out0 = conv_image*conv_multi0;
        temp_conv_out1 = conv_image*conv_multi1;
    end

    always@(posedge clk or posedge reset)
    begin   
        if(reset)
        begin
            conv_sum0 <= 40'sd0;
            conv_sum1 <= 40'sd0;
        end
        else if(conv_count == 0)
        begin
            conv_sum0 <= 40'sd0;
            conv_sum1 <= 40'sd0;
        end
        else if(conv_count < 10)
        begin
            conv_sum0 <= conv_sum0 + temp_conv_out0;
            conv_sum1 <= conv_sum1 + temp_conv_out1;
        end
        else if(conv_count == 10)
        begin
            conv_sum0 <= conv_sum0+ temp_conv_out0+ BIAS0;
            conv_sum1 <= conv_sum1+ temp_conv_out1+ BIAS1;
        end
    end
    
    assign conv_result0 = (conv_sum0[15]) ? $signed(conv_sum0[35:16]) + 20'sd1 : $signed(conv_sum0[35:16]);
    assign conv_result1 = (conv_sum1[15]) ? $signed(conv_sum1[35:16]) + 20'sd1 : $signed(conv_sum1[35:16]);

    //assign conv_result0 = (conv_sum0[15])? conv_sum0[35:16]+20'd1:conv_sum0[35:16];
    //assign conv_result1 = (conv_sum1[15])? conv_sum1[35:16]+20'd1:conv_sum1[35:16];
    //csel
    always@(*)
    begin
        csel=3'd0;
        case (next_state)
        L0_MEM0:    csel = 3'd1; //kernel0
        L0_MEM1:    csel = 3'd2; //kernel1
        POOLING_k0: csel = 3'd1; 
        POOLING_k1: csel = 3'd2; 
        L1_MEM0:    csel = 3'd3; //pooling0
        L1_MEM1:    csel = 3'd4; //pooling1
        FLAT_RD:    csel = (flat_cnt[0] == 0) ?3'd3:3'd4;            
        FLAT_WR:     csel = 3'd5; // Flatten     L2_MEM
        default:    csel = 3'd0; // idle
    endcase
    end
    //cwr
    always@(posedge clk or posedge reset)
    begin
        if(reset)
            cwr <= 1'd0;
        else if(next_state == RESULT0)
            cwr <= 1'd1;
        else if(next_state == L0_MEM0)
            cwr <= 1'd1;
        //pooling
        else if(pooling_count==4)
            cwr <= 1'd1;    
        else if(state == FLAT_WR)         
            cwr <= 1'd1;  
        else    
            cwr <= 1'd0;
    end 
    //crd
    always@(posedge clk or posedge reset)
    begin
        if(reset)
        begin
            crd <= 1'd0;
        end
        else if(next_state == POOLING_k0)
            crd <= 1'd1;
        else if(next_state == POOLING_k1)
            crd <= 1'd1;
        //              L1_MEM0     L1_MEM1
        else if(next_state == FLAT_WR)
         if (flat_cnt < 12'd1024) begin
            crd <= 1'd1;
        end else begin
            crd <= 1'd1;
        end
    end
    


    //caddr_wr
    always @(*) begin
    caddr_wr = 12'sd0;
    case (next_state)
        L0_MEM0:   caddr_wr = {conv_i, conv_j};
        L0_MEM1:   caddr_wr = {conv_i, conv_j}; 
        L1_MEM0:   caddr_wr = {2'b00,conv_i[5:1],conv_j[5:1]};
        L1_MEM1:   caddr_wr = {2'b00,conv_i[5:1],conv_j[5:1]};
        FLAT_WR:   caddr_wr = flat_cnt-1;     // L2_MEM       
        default:   caddr_wr = 12'd0;
    endcase
    end

    always @(*) begin
    cdata_wr = 20'sd0; // default
    case (next_state)
        L0_MEM0:   cdata_wr = (conv_sum0[39]) ? 20'sd0 : conv_result0;
        L0_MEM1:   cdata_wr = (conv_sum1[39]) ? 20'sd0 : conv_result1;
        L1_MEM0:   cdata_wr = pool_max;
        L1_MEM1:   cdata_wr = pool_max;
        FLAT_WR:   cdata_wr = flat_data;
        default:   cdata_wr = 20'sd0;
    endcase
end

   //caddr_rd        (pooling + flatten)
always @(posedge clk) begin
    if (reset) begin
        caddr_rd <= 12'd0;
    end else begin
        case (next_state)
            // -------- Pooling        --------
            POOLING_k0: begin
                case (pooling_count)
                    0: caddr_rd <= {conv_i       , conv_j};
                    1: caddr_rd <= {conv_i       , conv_j + 6'd1};
                    2: caddr_rd <= {conv_i + 6'd1, conv_j};
                    3: caddr_rd <= {conv_i + 6'd1, conv_j + 6'd1};
                    default: caddr_rd <= 12'd0;
                endcase
            end

            POOLING_k1: begin
                case (pooling_count)
                    0: caddr_rd <= {conv_i       , conv_j};
                    1: caddr_rd <= {conv_i       , conv_j + 6'd1};
                    2: caddr_rd <= {conv_i + 6'd1, conv_j};
                    3: caddr_rd <= {conv_i + 6'd1, conv_j + 6'd1};
                    default: caddr_rd <= 12'd0;
                endcase
            end
            FLAT_WR: begin
                //     flat_cnt     L1_MEM0 / L1_MEM1
                     caddr_rd <= read_ptr;
            end
            default: begin
                caddr_rd <= 12'd0;
            end
        endcase
     
    end
end

    //pool_max
    always @(posedge clk or posedge reset) begin
    if(reset)begin
        pool_max = 20'sd0;
    end else if (next_state == POOLING_k0||POOLING_k1) begin
        case (pooling_count)
            1: pool_max = cdata_rd;
            2: pool_max=(pool_max > cdata_rd)?pool_max:cdata_rd;
            3: pool_max=(pool_max > cdata_rd)?pool_max:cdata_rd;
            4: pool_max=(pool_max > cdata_rd)?pool_max:cdata_rd;
            5: pool_max=pool_max;
            default: pool_max = 20'sd0;
        endcase
    end
end

     //flat_cnt
    always @(posedge clk or posedge reset) begin
    if (reset) begin
        flat_cnt <= 12'd0;
        
    end else if (state == FLAT_WR) begin
        flat_cnt <= flat_cnt + 12'd1;   
    end
    end

    //flat_data
    always @(posedge clk or posedge reset) begin
    if (reset) begin
        flat_data <= 20'sd0;
    end else if (state == FLAT_WR) begin
        flat_data <= cdata_rd;                              
    end
    end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        read_ptr <= 0;
    end else if (next_state == FLAT_RD&&csel==4'd4) begin
        read_ptr <= read_ptr + 1;
    end
end

endmodule






