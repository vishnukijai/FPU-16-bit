
module divider16(
        input_a,
        input_b,
        output_z_ack,
        clk,
        rst,
        output_z,
        output_z_stb,
        input_a_ack,
        input_b_ack);

  input     clk;
  input     rst;

  input     [15:0] input_a;
  output    input_a_ack;

  input     [15:0] input_b;
  output    input_b_ack;

  output    [15:0] output_z;
  output    output_z_stb;
  input     output_z_ack;

  reg       s_output_z_stb;
  reg       [15:0] s_output_z;
  reg       s_input_a_ack;
  reg       s_input_b_ack;

  reg       [3:0] state;
  parameter get_a         = 4'd0,
            get_b         = 4'd1,
            unpack        = 4'd2,
            special_cases = 4'd3,
            normalise_a   = 4'd4,
            normalise_b   = 4'd5,
            divide_0      = 4'd6,
            divide_1      = 4'd7,
            divide_2      = 4'd8,
            divide_3      = 4'd9,
            normalise_1   = 4'd10,
            normalise_2   = 4'd11,
            round         = 4'd12,
            pack          = 4'd13,
            put_z         = 4'd14;

  reg       [15:0] a, b, z;
  reg       [10:0] a_m, b_m, z_m;
  reg       [6:0] a_e, b_e, z_e;
  reg       a_s, b_s, z_s;
  reg       guard, round_bit, sticky;
  reg       [24:0] quotient, divisor, dividend, remainder;
  reg       [5:0] count;

  always @(posedge clk)
  begin

    case(state)

      get_a:
      begin
        s_input_a_ack <= 1;
        if (s_input_a_ack) begin
          a <= input_a;
          s_input_a_ack <= 0;
          state <= get_b;
        end
      end

      get_b:
      begin
        s_input_b_ack <= 1;
        if (s_input_b_ack) begin
          b <= input_b;
          s_input_b_ack <= 0;
          state <= unpack;
        end
      end

      unpack:
      begin
        a_m <= a[9 : 0];
        b_m <= b[9 : 0];
        a_e <= a[14 : 10] - 15;
        b_e <= b[14 : 10] - 15;
        a_s <= a[15];
        b_s <= b[15];
        state <= special_cases;
      end

      special_cases:
      begin
        //if a is NaN or b is NaN return NaN 
        if ((a_e == 16  && a_m != 0) || (b_e == 16 && b_m != 0)) begin
          z[15] <= 1;
          z[14:10] <= 31;
          z[9] <= 1;
          z[8:0] <= 0;
          state <= put_z;
          //if a is inf and b is inf return NaN 
        end else if ((a_e == 16) && (b_e == 16)) begin
          z[15] <= 1;
          z[14:10] <= 31;
          z[9] <= 1;
          z[8:0] <= 0;
          state <= put_z;
        //if a is inf return inf
        end else if (a_e == 16) begin
          z[15] <= a_s ^ b_s;
          z[14:10] <= 31;
          z[9:0] <= 0;
          state <= put_z;
           //if b is zero return NaN
          if ($signed(b_e == -15) && (b_m == 0)) begin
            z[15] <= 1;
            z[14:10] <= 255;
            z[9] <= 1;
            z[8:0] <= 0;
            state <= put_z;
          end
        //if b is inf return zero
        end else if (b_e == 16) begin
          z[15] <= a_s ^ b_s;
          z[14:10] <= 0;
          z[9:0] <= 0;
          state <= put_z;
        //if a is zero return zero
        end else if (($signed(a_e) == -15) && (a_m == 0)) begin
          z[15] <= a_s ^ b_s;
          z[14:10] <= 0;
          z[9:0] <= 0;
          state <= put_z;
           //if b is zero return NaN
          //if (($signed(b_e) == -127) && (b_m == 0)) begin
           // z[31] <= 1;
          //  z[30:23] <= 255;
         //   z[22] <= 1;
          //  z[21:0] <= 0;
          //  state <= put_z;
          // end
        //if b is zero return inf
        end else if (($signed(b_e) == -15) && (b_m == 0)) begin
          z[15] <= a_s ^ b_s;
          z[14:10] <= 31;
          z[9:0] <= 0;
          state <= put_z;
        end else begin
          //Denormalised Number
          if ($signed(a_e) == -15) begin
            a_e <= -14;
          end else begin
            a_m[10] <= 1;
          end
          //Denormalised Number
          if ($signed(b_e) == -15) begin
            b_e <= -14;
          end else begin
            b_m[10] <= 1;
          end
          state <= normalise_a;
        end
      end

      normalise_a:
      begin
        if (a_m[10]) begin
          state <= normalise_b;
        end else begin
          a_m <= a_m << 1;
          a_e <= a_e - 1;
        end
      end

      normalise_b:
      begin
        if (b_m[10]) begin
          state <= divide_0;
        end else begin
          b_m <= b_m << 1;
          b_e <= b_e - 1;
        end
      end

      divide_0:
      begin
        z_s <= a_s ^ b_s;
        z_e <= a_e - b_e;
        quotient <= 0;
        remainder <= 0;
        count <= 0;
        dividend <= a_m << 14;
        divisor <= b_m;
        state <= divide_1;
      end

      divide_1:
      begin
        quotient <= quotient << 1;
        remainder <= remainder << 1;
        remainder[0] <= dividend[24];
        dividend <= dividend << 1;
        state <= divide_2;
      end

      divide_2:
      begin
        if (remainder >= divisor) begin
          quotient[0] <= 1;
          remainder <= remainder - divisor;
        end
        if (count == 23) begin
          state <= divide_3;
        end else begin
          count <= count + 1;
          state <= divide_1;
        end
      end

      divide_3:
      begin
        z_m <= quotient[13:3];
        guard <= quotient[2];
        round_bit <= quotient[1];
        sticky <= quotient[0] | (remainder != 0);
        state <= normalise_1;
      end

      normalise_1:
      begin
        if (z_m[10] == 0 && $signed(z_e) > -14) begin
          z_e <= z_e - 1;
          z_m <= z_m << 1;
          z_m[0] <= guard;
          guard <= round_bit;
          round_bit <= 0;
        end else begin
          state <= normalise_2;
        end
      end

      normalise_2:
      begin
        if ($signed(z_e) < -14) begin
          z_e <= z_e + 1;
          z_m <= z_m >> 1;
          guard <= z_m[0];
          round_bit <= guard;
          sticky <= sticky | round_bit;
        end else begin
          state <= round;
        end
      end

      round:
      begin
        if (guard && (round_bit | sticky | z_m[0])) begin
          z_m <= z_m + 1;
          if (z_m == 11'b11111111111) begin
            z_e <=z_e + 1;
          end
        end
        state <= pack;
      end

      pack:
      begin
        z[9 : 0] <= z_m[9:0];
        z[14 : 10] <= z_e[4:0] + 15;
        z[15] <= z_s;
        if ($signed(z_e) == -14 && z_m[10] == 0) begin
          z[14 : 10] <= 0;
        end
        //if overflow occurs, return inf
        if ($signed(z_e) > 15) begin
          z[9 : 0] <= 0;
          z[14 : 10] <= 31;
          z[15] <= z_s;
        end
        state <= put_z;
      end

      put_z:
      begin
        s_output_z_stb <= 1;
        s_output_z <= z;
        if (s_output_z_stb && output_z_ack) begin
          s_output_z_stb <= 0;
          state <= get_a;
        end
      end

    endcase

    if (rst == 1) begin
      state <= get_a;
      s_input_a_ack <= 0;
      s_input_b_ack <= 0;
      s_output_z_stb <= 0;
    end

  end
  assign output_z_stb = s_output_z_stb;
  assign output_z = s_output_z;

endmodule