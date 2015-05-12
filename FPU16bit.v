module FPU16(
        opcode,
        input_a,
        input_b,
        output_z_ack,
        clk,
        rst,
        output_z,
        output_z_stb,
        input_a_ack,
        input_b_ack);
input [2:0]opcode;
input 