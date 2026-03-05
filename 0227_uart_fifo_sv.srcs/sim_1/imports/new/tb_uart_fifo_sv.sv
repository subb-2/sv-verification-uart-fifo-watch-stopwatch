`timescale 1ns / 1ps

interface uf_interface (
    input logic clk
);

    parameter BAUD = 9600;
    parameter BAUD_PERIOD = (100_000_000 / BAUD) * 10;  // 예상 = 104_160

    logic       rst;
    logic       uart_rx;
    logic       uart_tx;
    logic       tx_done;

    //내부 관찰 
    logic [7:0] rx_data;
    logic [7:0] tx_data;
    logic       b_tick;

    logic       rx_done;
    logic       fifo_rx_push;
    logic       fifo_rx_pop;
    logic       fifo_rx_empty;

    logic       fifo_tx_push;
    logic       fifo_tx_pop;
    logic       fifo_tx_full;
    logic       fifo_tx_empty;

    logic       tx_start;
    logic       fifo_tx_busy;

    logic [7:0] rx_pop_data;
    logic [7:0] tx_push_data;

    property preset_check;
        @(posedge clk) rst |=> (rx_data == 0);
    endproperty
    reg_reset_check :
    assert property (preset_check)
    else $display("%t : Assert error : reset check", $time);

endinterface  //uf_interface

class transaction;

    rand bit [7:0] rx_data;

    constraint rand_no_zero {rx_data != 8'h00;}

    //rand int baud_scale; 

    //constraint baud_scale_percent {
    //    baud_scale inside {[10000:25000]};
    //}

    logic       rst;

    //내부 관찰 
    logic [7:0] tx_data;
    logic       b_tick;

    logic       rx_done;
    logic       fifo_rx_push;
    logic       fifo_rx_pop;
    logic       fifo_rx_empty;

    logic       fifo_tx_push;
    logic       fifo_tx_pop;
    logic       fifo_tx_full;
    logic       fifo_tx_empty;

    logic       tx_start;
    logic       fifo_tx_busy;
    logic       tx_done;

    logic [7:0] rx_pop_data;
    logic [7:0] tx_push_data;

    //logic       rx_fifo_pop_cp;
    //logic       tx_fifo_pop_cp;

    function void display(string name);
        $display(
            "%t : [%s] rx_data = %2h, rx_done = %h, tx_data = %2h, tx_done = %h, ",
            $time, name, rx_data, rx_done, tx_data, tx_done);
    endfunction  //new()
endclass  //transaction

class generator;

    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_ev;

    function new(mailbox#(transaction) gen2drv_mbox, 
            mailbox #(transaction) gen2scb_mbox, event gen_next_ev);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction  //new()

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            assert (tr.randomize())
            else $display("[gen] tr.randomize() error!!!");
            gen2drv_mbox.put(tr);
            gen2scb_mbox.put(tr);
            tr.display("gen");
            @(gen_next_ev);
        end
    endtask  //run
endclass  //generator

class driver;

    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uf_interface uf_if;

    //longint baud_sc_per;
    //longint BAUD_sc_per;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uf_interface uf_if);
        this.gen2drv_mbox = gen2drv_mbox;
        this.uf_if = uf_if;
    endfunction  //new()

    task preset();
        uf_if.rst = 1;
        uf_if.uart_rx = 1;
        repeat (10) @(negedge uf_if.clk);
        uf_if.rst = 0;
        repeat (10) @(negedge uf_if.clk);
    endtask  //preset


    //PC가 data 전송 
    task run();
        forever begin
            //in mailbox
            gen2drv_mbox.get(tr);

            //baud_sc_per = (uf_if.BAUD_PERIOD * tr.baud_scale) / 100;
            //BAUD_sc_per = (100_000_000 / tr.baud_scale) * 10;

            @(posedge uf_if.clk);
            #1;
            tr.display("drv");

            //rx data 전송
            uf_if.uart_rx = 1'b0; // rx 선을 0으로 내려서 통신 시작 알림
            #(uf_if.BAUD_PERIOD);
            //#(BAUD_sc_per);

            //random data rx 선으로 밀어 넣기 
            for (int i = 0; i < 8; i++) begin
                uf_if.uart_rx = tr.rx_data[i];
                #(uf_if.BAUD_PERIOD);
                //#(BAUD_sc_per);
            end
            uf_if.uart_rx = 1'b1;
            #(uf_if.BAUD_PERIOD);
            //#(BAUD_sc_per);

            // 수정 후 (%0t 를 %0d 로 변경)
           // $display("%t [DRV] baud_scale = %0d (= %0.2f%%), BAUD_sc_per = %0d ns",
                //$time, tr.baud_scale, (tr.baud_scale-9600)/100.0, BAUD_sc_per);
            $display("%t [DRV] BAUD = %0d (= %0.2f%%), BAUD_ns = %0d ns",
                $time, uf_if.BAUD_PERIOD, uf_if.BAUD_PERIOD/100.0, uf_if.BAUD_PERIOD);

            // 약간의 여유 시간을 주어 FIFO 상태가 업데이트되게 함
            repeat (5) @(negedge uf_if.clk); //이것 때문에 FIFO가 full 안 나는 거라고?
            //repeat ($urandom_range(0,5))
            //@(negedge uf_if.clk);
            //#(BAUD_sc_per * 15);
        end
    endtask

endclass  //driver

class monitor;

    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual uf_interface uf_if;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uf_interface uf_if);
        this.mon2scb_mbox = mon2scb_mbox;
        this.uf_if = uf_if;
    endfunction  //new()

    // monitor 클래스 내부
    task run();
        // join_none을 써야 environment의 다른 루프들이 돌아감 
        fork
            // [RX 모니터]
            forever begin
                transaction tr_rx;
                @(posedge uf_if.rx_done);
                #1;
                tr_rx = new;
                @(negedge uf_if.clk);  // 샘플링 안정화
                tr_rx.rx_data = uf_if.rx_data;
                tr_rx.tx_data = uf_if.tx_data;

                tr_rx.b_tick = uf_if.b_tick;

                tr_rx.rx_done = uf_if.rx_done;

                $display("%t [MON_RX] RX_DATA = %2h, RX_DONE = %h",
                         $time, uf_if.rx_data, uf_if.rx_done);
                mon2scb_mbox.put(tr_rx);
            end

            //rx_push_data
            forever begin
                transaction rx_push;
                @(posedge uf_if.fifo_rx_push);
                #1;
                @(posedge uf_if.clk);
                #1;
                rx_push = new;

                rx_push.fifo_rx_push = uf_if.fifo_rx_push;
                rx_push.fifo_rx_empty = uf_if.fifo_rx_empty;
                
                $display("%t [MON_RX_PUSH] ", $time);
                mon2scb_mbox.put(rx_push);
            end

            //rx_pop_data + tx_push_data
            forever begin
                transaction rx_empty;
                @(negedge uf_if.fifo_rx_empty);
                #1;
                @(posedge uf_if.clk);
                #1;
                rx_empty = new;

                rx_empty.rx_pop_data = uf_if.rx_pop_data;
                tx_empty.tx_push_data = uf_if.tx_push_Data;

                mon2scb_mbox.put(rx_empty);
            end

            //tx_pop_data
            forever begin
                transaction tx_pop;
                @(posedge uf_if.tx_start);
                #1;
                @(negedge uf_if.clk);
                tx_pop = new;

                tx_pop.tx_data = uf_if.tx_data;  // 찰나의 팝 데이터(예: 61) 캡처
                tx_pop.rx_data = uf_if.rx_data;
                tx_pop.fifo_rx_empty = uf_if.fifo_rx_empty;
                tx_pop.fifo_tx_empty = uf_if.fifo_tx_empty;
                //tx_pop.tx_fifo_pop_cp = 1;  // 찰나의 순간 플래그 ON!

                mon2scb_mbox.put(tx_pop);
            end

            // [TX 모니터] - 실제 출력되는 데이터를 감시
            forever begin
                transaction tr_tx;
                // tx_pop : 데이터가 FIFO에서 빠져나가는 순간을 감시
                @(posedge uf_if.tx_done);
                #1;
                tr_tx = new;
                @(negedge uf_if.clk);
                tr_tx.rx_data = uf_if.rx_data;
                tr_tx.tx_data = uf_if.tx_data;  // FIFO 출력값 캡처

                tr_tx.b_tick = uf_if.b_tick;

                tr_tx.tx_done = uf_if.tx_done;

                $display(
                    "%t [MON_TX] DATA = %2h, DONE = %h, PUSH = %h,  EMPTY = %h, FULL = %h",
                    $time, uf_if.tx_data, uf_if.tx_done, uf_if.fifo_tx_push,
                    uf_if.fifo_tx_empty, uf_if.fifo_tx_full);
                mon2scb_mbox.put(tr_tx);
            end

            forever begin
                @(posedge uf_if.fifo_tx_full); // FULL이 1로 뜨는 순간
                
                $display("______________________________________________________");
                $display("*** %t : FIFO FULL!!! ***", $time);
                $display("*** CURRENT DATA: %h ***", uf_if.rx_data);
                $display("______________________________________________________");
            end

        join_none

    endtask

    //endtask  //run

endclass  //monitor

class scoreboard;

    transaction tr;

    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;

    int compared_cnt = 0;  // 현재까지 비교한 개수
    //int tx_done_cnt = 0; // tx_done 비교 시점 
    event gen_next_ev;  // 테스트 종료를 알리는 이벤트

    //queue 
    logic [7:0] uf_queue[$];  //size 지정 안하면 무한대 
    logic [7:0] uf_queue_ur[$];
    logic [7:0] fifo_data;
    logic [7:0] fifo_compare;
    logic [7:0] compare_data;
    logic [7:0] rx_data_o;

    int INTERNAL_pass_cnt, INTERNAL_fail_cnt;
    int FINAL_pass_cnt, FINAL_fail_cnt;

    function new(mailbox#(transaction) mon2scb_mbox, 
                mailbox #(transaction) gen2scb_mbox, event gen_next_ev);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction  //new()

    task run();
        fork
            forever begin
                gen2scb_mbox.get(tr);
                uf_queue.push_back(tr.rx_data); // 원본 데이터 저장
                uf_queue.push_back(tr.rx_data);
                $display("%t : [scb_rx_data] rx_data = %h", $time, tr.rx_data);
            end
        join_none

        forever begin
            mon2scb_mbox.get(tr);

            //rx_data 비교
            if (tr.tx_done) begin
                rx_data_o = tr.rx_data;
            end

            // tx_fifo_pop_data 비교 
            if (tr.tx_start) begin
                tr.display("scb_pop_data");
                fifo_data = tr.rx_data;
                fifo_compare = tr.tx_data; 
                if (fifo_compare === fifo_data) begin
                    $display(
                        "%t : [FIFO_DATA_MATCH] FIFO trans Success! (Data: %h) PASS!!!",
                        $time, tr.tx_data);
                    $display(
                        "%t : [FIFO_DATA_MATCH] fifo_rx_empty = %h, fifo_tx_empty = %h",
                        $time, tr.fifo_rx_empty, tr.fifo_tx_empty);
                    INTERNAL_pass_cnt++;
                end else begin
                    $display(
                        "%t : [FIFO_DATA_FAIL] FIFO trans Fail! (Exp: %h, Act: %h)",
                        $time, fifo_data, fifo_compare);
                    INTERNAL_fail_cnt++;
                end
            end

            //rx_fifo_push_data 비교
            if (tr.fifo_rx_push) begin
                
            end

            //rx_fifo_pop_data + tx_fifo_push_data
            if (tr.fifo_rx_empty) begin
                
            end

            // TX data가 왔을 때 꺼내서 비교 
            if (tr.tx_done) begin
                tr.display("tx_data_compare");
                if (uf_queue.size() > 0) begin
                    // Act 값이 xx가 아닐 때만 queue에서 꺼내서 비교
                    if (tr.tx_data !== 8'hxx) begin
                    //if(tx_done_cnt >=3) begin
                        compare_data = uf_queue.pop_front();
                        compared_cnt++;
                        if (compare_data === tr.tx_data) begin
                            $display("PASS!!! (Exp: %h, Act: %h)",
                            compare_data, tr.tx_data);
                            FINAL_pass_cnt++;
                        end else begin
                            $display(
                                "FAIL!!! (Exp:%h, Act:%h)",
                                compare_data,
                                tr.tx_data
                            );
                            FINAL_fail_cnt++;
                        end
                    //end
                    end else begin
                        $display("%t : [SCB] Output xx, skipping compare.", $time);
                    end
                end
            end
            ->gen_next_ev;
        end
    endtask

endclass  //scoreboard

class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;

    event gen_next_ev;

    int i;

    function new(virtual uf_interface uf_if);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen2scb_mbox = new;

        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_ev);
        drv = new(gen2drv_mbox, uf_if);
        mon = new(mon2scb_mbox, uf_if);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_ev);

    endfunction  //new()

    task run();
        i = 10;
        drv.preset();

        fork
            gen.run(10);
            drv.run();
            mon.run();
            scb.run();
        join_any

        fork
            begin
                wait (scb.compared_cnt >= (i - 3)); 
                $display("\n%t : SUCCESS", $time);
            end

        join_any

        disable fork;
        
            #100;
            
            $display("______________________________________");
            $display("****   UART + FIFO VERIFICATION   ****");
            $display("--------------------------------------");
            $display("**    Total test cnt      = %8d     **", i);
            $display("**    Current Time        = %t     **", $time);
            $display("**    COMPARED cnt        = %8d     **", scb.compared_cnt);
            $display("**    INTERNAL pass cnt   = %8d     **", scb.INTERNAL_pass_cnt);
            $display("**    INTERNAL fail cnt   = %8d     **", scb.INTERNAL_fail_cnt);
            $display("**    FINAL pass cnt      = %8d     **", scb.FINAL_pass_cnt);
            $display("**    FINAL fail cnt      = %8d     **", scb.FINAL_fail_cnt);
            $display("--------------------------------------");

        $stop;
    endtask  //run
endclass  //environment

module tb_uart_fifo_sv ();

    logic clk;

    uf_interface uf_if (clk);
    environment env;

    uart_top dut (
        .clk(clk),
        .rst(uf_if.rst),
        .uart_rx(uf_if.uart_rx),
        .uart_tx(uf_if.uart_tx),
        .tx_done(uf_if.tx_done)
    );

    // ===============================
    // 계층적 경로(.)를 통한 강제 연결
    // ===============================

    assign uf_if.rx_data = dut.w_rx_data;
    assign uf_if.tx_data = dut.w_tx_fifo_pop_data;
    assign uf_if.b_tick = dut.w_b_tick;

    assign uf_if.rx_done = dut.w_rx_done;  //
    assign uf_if.fifo_rx_push = dut.w_rx_done;  //
    assign uf_if.fifo_rx_pop = ~dut.w_tx_fifo_full;
    assign uf_if.fifo_rx_empty = dut.w_rx_fifo_empty;  //

    assign uf_if.fifo_tx_push = ~dut.w_rx_fifo_empty;
    assign uf_if.fifo_tx_pop = ~dut.w_tx_busy;
    assign uf_if.fifo_tx_full = dut.w_tx_fifo_full;  //
    assign uf_if.fifo_tx_empty = dut.w_tx_fifo_empty;  //

    assign uf_if.tx_start = ~dut.w_tx_fifo_empty;
    assign uf_if.fifo_tx_busy = dut.w_tx_busy;  //

    assign uf_if.rx_pop_data = dut.w_rx_fifo_pop_data;
    assign uf_if.tx_push_data = dut.w_rx_fifo_pop_data;

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        env = new(uf_if);
        env.run();
    end

endmodule
