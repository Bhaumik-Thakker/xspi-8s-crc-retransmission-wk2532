//! @file xSPI.v
//! @brief Top-level and submodules for a simple SPI-like protocol (xSPI) with controller and slave.

/**
 * @module xspi_top
 * @brief Top-level module connecting xSPI controller and slave via a shared IO bus.
 * @param clk     System clock
 * @param rst_n   Active-low reset
 * @param start   Start transaction
 * @param command 8-bit command
 * @param address 48-bit address
 * @param wr_data 64-bit data to write
 * @param rd_data 64-bit data read
 * @param done    Transaction done flag
 * @param ready   Slave ready flag
 */
module xspi_top (
    input  wire        clk,      //!< System clock
    input  wire        rst_n,    //!< Active-low reset
    input  wire        start,    //!< Start transaction
    //input  wire        rw,
    input  wire [7:0]  command,  //!< 8-bit command
    input  wire [47:0] address,  //!< 48-bit address
    input  wire [63:0] wr_data,  //!< 64-bit data to write
    output wire [63:0] rd_data,  //!< 64-bit data read
    output wire        done,     //!< Transaction done flag
    output wire        ready,    //!< Slave ready flag
    output wire        crc_ca_match_slave,
    output wire        crc_ca_error_slave,
    output wire        crc_ca_match_master,
    output wire        crc_ca_error_master,
    output wire        crc_data_match_master,
    output wire        crc_data_error_master,
    output wire        crc_data_match_slave,
    output wire        crc_data_error_slave
);

    // Internal bus and control signals
    wire        cs_n;           //!< Chip select (active low)
    wire        sck;            //!< SPI clock
    wire [7:0]  master_io_out;  //!< Controller output to bus
    wire [7:0]  slave_io_out;   //!< Slave output to bus
    wire        master_io_oe;   //!< Controller output enable
    wire        slave_io_oe;    //!< Slave output enable
    wire [7:0]  io_bus;         //!< Shared IO bus
    // CRC signals
   // wire        crc_ca_match, crc_data_match, crc_ca_error, crc_data_error;

    // Simplified IO bus - no tri-state logic
    assign io_bus = master_io_oe ? master_io_out : 
                    slave_io_oe  ? slave_io_out  : 8'h00;

    /**
     * @brief xSPI controller (master)
     */
    xspi_sopi_controller master (
        .clk(clk),
        .rst_n(rst_n),
        .cs_n(cs_n),
        .sck(sck),
        .io_out(master_io_out),
        .io_in(io_bus),
        .io_oe(master_io_oe),
        .start(start),
        //.rw(rw),
        .command_in(command),
        .address_in(address),
        .wr_data_in(wr_data),
        .rd_data(rd_data),
        .done(done),
        .data_strobe(data_strobe),
        .crc_ca_match(crc_ca_match_master),
        .crc_data_match(crc_data_match_master),
        .crc_ca_error(crc_ca_error_master),
        .crc_data_error(crc_data_error_master),
        .crc_ca_error_slave(crc_ca_error_slave),
        .crc_data_error_slave(crc_data_error_slave)
    );

    /**
     * @brief xSPI slave
     */
    xspi_sopi_slave slave (
        .clk(clk),
        .rst_n(rst_n),
        .cs_n(cs_n),
        .sck(sck),
        .io_out(slave_io_out),
        .io_in(io_bus),
        .io_oe(slave_io_oe),
        .ready(ready),
        .data_strobe(data_strobe),
        .crc_ca_match(crc_ca_match_slave),
        .crc_data_match(crc_data_match_slave),
        .crc_ca_error(crc_ca_error_slave),
        .crc_data_error(crc_data_error_slave),
        .crc_ca_error_master(crc_ca_error_master),
        .crc_data_error_master(crc_data_error_master)
    );


endmodule