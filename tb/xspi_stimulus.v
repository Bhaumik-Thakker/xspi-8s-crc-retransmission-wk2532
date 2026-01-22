module xspi_stimulus;

    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Control signals
    reg start;
    reg [7:0] command;
    reg [47:0] address;
    reg [63:0] wr_data;
    wire [63:0] rd_data;
    wire done;
    wire ready;
    
    // CRC signals
    wire crc_ca_match_slave;
    wire crc_ca_error_slave;
    wire crc_data_match_master;
    wire crc_data_error_master;
    wire crc_data_match_slave;
    wire crc_data_error_slave;
    wire crc_ca_match_master;
    wire crc_ca_error_master;

    // Instantiate the DUT
    xspi_top xspi_top (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .command(command),
        .address(address),
        .wr_data(wr_data),
        .rd_data(rd_data),
        .done(done),
        .ready(ready),
        .crc_ca_match_slave(crc_ca_match_slave),
        .crc_ca_error_slave(crc_ca_error_slave),
        .crc_ca_match_master(crc_ca_match_master),
        .crc_ca_error_master(crc_ca_error_master),
        .crc_data_match_master(crc_data_match_master),
        .crc_data_error_master(crc_data_error_master),
        .crc_data_match_slave(crc_data_match_slave),
        .crc_data_error_slave(crc_data_error_slave)
    );

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end


    // VCD dump for waveform viewing
    initial begin
        $dumpfile("xspi_tb.vcd");
        $dumpvars(0, xspi_stimulus);
    end

    initial begin
        $display("=== xSPI Master/Slave Simulation Start ===");
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;

        // --- WRITE ---
        @(posedge clk);
        command = 8'hA5;
        address = 48'h6655443322AB;
        wr_data = 64'h1122334455667788;
        //rw = 0;
        start = 1;

        @(posedge clk);
        start = 0;

        wait (done);
        $display("[WRITE] Wrote %h to address %h", wr_data, address);
        $display("[WRITE] CRC CA match_slave: %b, CRC CA error_slave: %b, CRC DATA match_master: %b, CRC DATA error_master: %b, CRC DATA match_slave: %b, CRC DATA error_slave: %b", crc_ca_match_slave, crc_ca_error_slave, crc_data_match_master, crc_data_error_master, crc_data_match_slave, crc_data_error_slave);

        #50;

        // --- READ ---
        @(posedge clk);
        command = 8'hFF;
        address = 48'h6655443322AB;
        wr_data = 64'h0;
       // rw = 1;
        @(posedge clk);
        start = 1;
        @(posedge clk);
      @(posedge clk);
        start = 0;

        wait (done);
        $display("[READ] Read %h from address %h", rd_data, address);
        $display("[WRITE] CRC CA match_slave: %b, CRC CA error_slave: %b, CRC DATA match_master: %b, CRC DATA error_master: %b, CRC DATA match_slave: %b, CRC DATA error_slave: %b", crc_ca_match_slave, crc_ca_error_slave, crc_data_match_master, crc_data_error_master, crc_data_match_slave, crc_data_error_slave);

        if (rd_data == 64'h1122334455667788) begin
            $display("✅ PASS: Read data matches written data.");
        end else begin
            $display("❌ FAIL: Read data mismatch!");
        end

        #100;
        $finish;
    end

  initial begin 
    #2000;
    $finish;
  end
  
    // Internal storage to remember the last write operation
    // This allows us to verify the subsequent read operation.
    reg [63:0] last_wr_data;
    reg [47:0] last_address;

    // The main checking logic, triggered when a transaction completes.
    // We use @(posedge done) because 'done' is a single-cycle pulse.
    always @(posedge done) begin
        if (rst_n) begin
            // Check which operation was performed based on the command code
            // provided by the stimulus.

            // --- WRITE Operation Check ---
            if (command == 8'hA5) begin
                $display("--------------------------------------------------");
                $display("[MONITOR] WRITE Transaction Report");
                $display("  Address:    %h", address);
                $display("  Wrote Data: %h", wr_data);
                $display("  Slave CA CRC Status:   Match=%b, Error=%b", crc_ca_match_slave, crc_ca_error_slave);
                $display("  Slave Data CRC Status: Match=%b, Error=%b", crc_data_match_slave, crc_data_error_slave);
                $display("--------------------------------------------------");

                // Store the written data and address for later read verification
                last_wr_data <= wr_data;
                last_address <= address;
            end

            // --- READ Operation Check ---
            else if (command == 8'hFF) begin
                $display("--------------------------------------------------");
                $display("[MONITOR] READ Transaction Report");
                $display("  Address:       %h", address);
                $display("  Read Data:     %h", rd_data);
                $display("  Expected Data: %h", last_wr_data);
                $display("  Slave CA CRC Status:    Match=%b, Error=%b", crc_ca_match_slave, crc_ca_error_slave);
                $display("  Master Data CRC Status: Match=%b, Error=%b", crc_data_match_master, crc_data_error_master);

                // Verify that the read address matches the last write address
                if (address == last_address) begin
                    // Verify that the read data matches the last written data
                    if (rd_data == last_wr_data) begin
                        $display("✅ [MONITOR] PASS: Read data matches written data.");
                    end else begin
                        $display("❌ [MONITOR] FAIL: Read data mismatch!");
                    end
                end else begin
                    $display("❌ [MONITOR] FAIL: Read address mismatch!");
                end
                $display("--------------------------------------------------");
            end
        end
    end
endmodule
