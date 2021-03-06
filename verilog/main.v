`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////

// HeartAware
// M. Holachek and N. Singh
// 6.111 Final Project, Fall 2015
// https://github.com/holachek/heartaware

// Module: Main
// Description: Top Level HeartAware Module

//////////////////////////////////////////////////////////////////////////////////


// MODULE DEFINITION
//////////////////////////////////////////////////////////////////////////////////
module heartaware(

  // For hardware mapping constraints, see XDC file.

  // master clock
  input CLK100MHZ,

  // switches
  input [15:0] SW, 

  // directional buttons
  input BTNU,
  input BTND,
  input BTNL,
  input BTNR,
  input BTNC,

  // RGB LED
  output reg LED16_R, LED16_G, LED16_B, 
  output reg LED17_R, LED17_G, LED17_B, 

  // debug LEDs
  output reg [15:0] LED,

  // analog input module
  output [7:0] JA, // level shifted ADC_OUT[7:0]
  output [7:0] JB,
  // JB[0] active low CS for ADC,
  // JB[2] active low RD for ADC,
  // JB[4] active low WR for ADC,
  // JB[6] active low INTR for ADC,
  // sensor connect detection
  // pins JB[3], JB[5], JB[7] disconnected. to use, edit constraints file.
  input  [7:0] JC,
  output [7:0] JD,

  // 7-segment LED
  output [7:0] SEG,
  output [7:0] AN,

  // video
  output [3:0] VGA_R,
  output [3:0] VGA_G,
  output [3:0] VGA_B,
  output VGA_HS,
  output VGA_VS,

  // audio
  output AUD_PWM,
  output AUD_SD, // PWM audio enable

  // SD card
  input SD_CD,
  output SD_RESET,
  output SD_SCK,
  output SD_CMD, 
  inout [3:0] SD_DAT
  );

// CLOCKS, SYNC, & RESET
//////////////////////////////////////////////////////////////////////////////////
// create system and peripheral clocks, synced switches, master system reset

  wire master_reset;
  wire master_halt;

  wire clk_100mhz = CLK100MHZ; // master clock, connected to hardware crystal oscillator
  wire clk_65mhz; // VGA clock
  wire clk_25mhz; // SD clock
  wire clk_32khz; // audio sample rate clock
  wire clk_1khz;  // pulse ox sample clock
  wire clk_100hz; 
  wire clk_1hz;
  wire clk_point_2hz;
      
  clk_wiz_0 clk_65mhz_module(.clk_100mhz(clk_100mhz), .clk_65mhz(clk_65mhz), .reset(master_clock_reset));
  clock_divider clk_25mhz_module(.clk_in(clk_100mhz), .clk_out(clk_25mhz), .divider(32'd2), .reset(master_clock_reset)); // 100_000_000 / (25_000_000*2) = 2
  clock_divider clk_32khz_module(.clk_in(clk_100mhz), .clk_out(clk_32khz), .divider(32'd1563), .reset(master_clock_reset)); // 100_000_000 / (32_000*2) = 1563
  clock_divider clk_1khz_module(.clk_in(clk_100mhz), .clk_out(clk_1khz), .divider(32'd50_000), .reset(master_clock_reset)); // 100_000_000 / (32_000*2) = 1563
  clock_divider clk_100hz_module(.clk_in(clk_100mhz), .clk_out(clk_100hz), .divider(32'd500_000), .reset(master_clock_reset));
  clock_divider clk_1hz_module(.clk_in(clk_100mhz), .clk_out(clk_1hz), .divider(32'd200_000_000), .reset(master_clock_reset));
  clock_divider clk_point_2hz_module(.clk_in(clk_100mhz), .clk_out(clk_point_2hz), .divider(32'd1_000_000_000), .reset(master_clock_reset));

  wire [15:0] sw_synced;
  genvar i;
  generate   for(i=0; i<16; i=i+1) 
    begin: gen_modules  // generate 16 synchronize modules
      synchronize s(clk_100mhz, SW[i], sw_synced[i]); // WARNING! must be synced to master 100 MHz clock
                                                      // otherwise reset will stop clocks and halt CPU in reset state
    end
  endgenerate

  assign master_reset = sw_synced[15];
 // assign master_halt = sw_synced[14];

     
  reg [2:0] system_status = 3;
  // 0 = paused
  // 1 = run
  // 2 = error
  // 3 = startup



// DEBOUNCE OBJECTS
//////////////////////////////////////////////////////////////////////////////////
// create a synchronous, debounced pulse from async inputs

  wire btn_up, btn_down, btn_center, btn_left, btn_right;

  debounce up(.reset(master_reset), .clock(clk_25mhz), .noisy(BTNU), .clean(btn_up));
  debounce down(.reset(master_reset), .clock(clk_25mhz), .noisy(BTND), .clean(btn_down));
  debounce center(.reset(master_reset), .clock(clk_25mhz), .noisy(BTNC), .clean(btn_center));
  debounce left(.reset(master_reset), .clock(clk_25mhz), .noisy(BTNL), .clean(btn_left));
  debounce right(.reset(master_reset), .clock(clk_25mhz), .noisy(BTNR), .clean(btn_right));





// 7 SEGMENT DISPLAY
//////////////////////////////////////////////////////////////////////////////////
// 7 segment display related utilities

  reg [31:0] display_data;
  wire [6:0] display_segments;
  
  display_8hex display(.clk(clk_100mhz), .data(display_data), .seg(display_segments), .strobe(AN));
  
  assign SEG[6:0] = display_segments;
  assign SEG[7] = 1'b1;   // decimal point off




// SIGNAL RECORDING
//////////////////////////////////////////////////////////////////////////////////
// Signal recording
    reg [7:0] signal_in;
    
	//make registers to hold intermediate signals
	reg ena = 1;
	reg wea; initial wea = 1;
	reg enb; initial enb = 1;
	reg [9:0] addra; initial addra = 0;
	reg [9:0] addrb; initial addrb = 0;
	wire signed [8:0] doutb_lp;
	
	//outputs for debugging
	assign JA[7:0] = signal_lp[7:0];
	
	
	//provide clock to pulse oximeter
	assign JD[7] = clk_1khz;
	assign JD[6] = peak;
	
	//read in pulse oximeter signal values
	always @(posedge clk_100hz) begin
	   signal_in <= {JC[7], JC[3], JC[6], JC[2], JC[5], JC[1], JC[4], JC[0]};
	   addra <= addra+1;
	end




// SIGNAL PROCESSING
//////////////////////////////////////////////////////////////////////////////////
// Signal processing modules

    wire sp_ready;
    wire signed [18:0] signal_lp_mult;
    wire signed [8:0] signal_lp;
    
    reg [2:0] ready_sync;
    always @ (posedge clk_65mhz) begin    
        ready_sync <= {ready_sync[1:0], clk_100hz};
    end
    assign sp_ready = ready_sync[1] & ~ready_sync[2];
    
    always@(posedge clk_100hz) begin
        LED[15] <= sp_ready;
    end
    
    //instantiate low pass filter
    fir31_lp lowpass_filter(.clock(clk_65mhz),.reset(master_reset),.ready(sp_ready),.x(signal_in),.y(signal_lp_mult));
    assign signal_lp = signal_lp_mult[18:10];
	
    
    //make memory to hold lp signal
    blk_mem_gen_4 signal_memory (
      .clka(clk_100hz),    // input wire clka
      .wea(wea),      // input wire [0 : 0] wea
      .addra(addra),  // input wire [9 : 0] addra
      .dina(signal_lp),    // input wire [7 : 0] dina
      .clkb(clk_65mhz),    // input wire clkb
      .enb(enb),      // input wire enb
      .addrb(addrb),  // input wire [9 : 0] addrb
      .doutb(doutb_lp)  // output wire [7 : 0] doutb
    );
    
    reg mf_wea;
    reg [6:0] mf_counter; initial mf_counter <= 0;
    wire [6:0] mf_counter_reverse;
    
    //set up counters to write values to match filter
    always @(posedge clk_100hz) begin
        if(SW[13]==1 && mf_counter <= 126) begin
            mf_counter <= mf_counter+1;
            mf_wea <= 1;
        end
        else begin
            mf_counter <= 0;
            mf_wea <= 0;
        end
    end
    assign mf_counter_reverse = 126-mf_counter;
   
    //set up counters to read values to use in match filtering  
    reg [6:0] mf_index;
    reg [6:0] mf_offset;
    wire signed [8:0] mf_coeff; 
    wire signed [18:0] signal_mf;

    always @(posedge clk_65mhz) begin
        if(sp_ready) begin
            mf_offset <= mf_offset+1;
            mf_index <= 0;
        end
        else begin
		  if(mf_index<=126) begin		
            mf_index <= mf_index+1;
          end
       end
    end
    
    wire [6:0] mf_address;
    assign mf_address = mf_offset-mf_index; 
    //make memory to hold match filter coefficients
    match_filter_coeffs mf_coeffs (
          .clka(clk_100hz),    // input wire clka
          .wea(mf_wea),      // input wire [0 : 0] wea
          .addra(mf_counter_reverse),  // input wire [6 : 0] addra
          .dina(signal_lp),    // input wire [7 : 0] dina
          .clkb(clk_65mhz),    // input wire clkb
          .enb(enb),
          .addrb(mf_address),  // input wire [6 : 0] addrb
          .doutb(mf_coeff)  // output wire [7 : 0] doutb
        );
    //always @(posedge clk_65mhz) mf_coeff <= signal_lp;
    
    fir128_match mf(.clock(clk_65mhz),.reset(master_reset),.ready(sp_ready),.coeff_mf(mf_coeff),.index(mf_index),.offset(mf_offset),.x(signal_lp),.y(signal_mf));
    
    wire signed [18:0] doutb_mf_mult;
    wire signed [8:0] doutb_mf;
    //make memory to hold outputs from match filter
        //make memory to hold signal
    blk_mem_gen_3 mf_memory(
      .clka(clk_100hz),    // input wire clka
      .ena(ena),      // input wire ena
      .wea(wea),      // input wire [0 : 0] wea
      .addra(addra),  // input wire [9 : 0] addra
      .dina(signal_mf),    // input wire [15 : 0] dina
      .clkb(clk_65mhz),    // input wire clkb
      .enb(enb),      // input wire enb
      .addrb(addrb),  // input wire [9 : 0] addrb
      .doutb(doutb_mf_mult)  // output wire [15 : 0] doutb
    );
    
    assign doutb_mf = doutb_mf_mult[18:10];
    
    wire [10:0] current_count;
    wire peak;
    wire [7:0] hr;
    
    hr_calculator hr_calc(.clock(clk_100hz),.reset(master_reset),.signal(signal_lp),
        .num_elapsed(current_count),.peak(peak),.hr(hr));

    reg [7:0] hr_history [15:0];
    reg [7:0] hr_average; 
    reg [7:0] hr_scaled;
    reg [7:0] hr_final;
    reg [11:0] hr_sum;
    
    
    always @ (posedge peak) begin
    
        // Limit range of values displayed, in case filter has a hard time picking up signal
        if (SW[10] && system_status != 0) begin
        
            if (hr_average > 110) begin
                hr_scaled <= 8'd110;
            end else if (hr_average < 50) begin
                hr_scaled <= 8'd50;
            end else begin
                hr_scaled <= hr_average;
            end
            
        
        end
    
    hr_history[15] <= hr_history[14];
    hr_history[14] <= hr_history[13];
    hr_history[13] <= hr_history[12];
    hr_history[12] <= hr_history[11];
    hr_history[11] <= hr_history[10];
    hr_history[10] <= hr_history[9];
    hr_history[9] <= hr_history[8];
    hr_history[8] <= hr_history[7];
    hr_history[7] <= hr_history[6];
    hr_history[6] <= hr_history[5];
    hr_history[5] <= hr_history[4];
    hr_history[4] <= hr_history[3];
    hr_history[3] <= hr_history[2];
    hr_history[2] <= hr_history[1];
    hr_history[1] <= hr_history[0];
    hr_history[0] <= hr;
    hr_sum <= (hr_history[0]+hr_history[1]+hr_history[2]
                    +hr_history[3]+hr_history[4]+hr_history[5]
                    +hr_history[6]+hr_history[7]+hr_history[8]+hr_history[9]+hr_history[10]
                                        +hr_history[11]+hr_history[12]+hr_history[13]
                                        +hr_history[14]+hr_history[15]);
                                        
    hr_average <= hr_sum[11:4];
    
    end

    always@(posedge clk_100hz) begin
	   display_data[23:0] <= hr_sum;
	   display_data[31:24] <= hr_average;
	end    




// VIDEO
//////////////////////////////////////////////////////////////////////////////////
// create all objects related to VGA video display
    
    wire [10:0] hcount;
    reg  [9:0] hcount_offset; initial hcount_offset = 0;
    reg  [9:0] hcount_sliding; 
    wire [9:0] vcount;
    wire blank;
    wire hsync, vsync, at_display_area;
    xvga xvga1(.vga_clock(clk_65mhz),.hcount(hcount),.vcount(vcount),
          .hsync(hsync),.vsync(vsync),.blank(blank),.at_display_area(at_display_area));
    
    wire [3:0] r_out;
    wire [3:0] g_out;
    wire [3:0] b_out;

    wire [9:0] v_val;
    wire [9:0] v_val2;
    wire in_region;
    
   reg [3:0] r_out_reg;
   reg [3:0] g_out_reg;
   reg [3:0] b_out_reg;
   reg hsync_reg, vsync_reg;
    
    always @ (posedge clk_100hz) begin
        if (system_status == 1) hcount_offset <= hcount_offset+1;
    end
    
    always @ (posedge clk_65mhz) begin
            if (system_status == 1) begin

        hcount_sliding <= hcount+hcount_offset;
        addrb <= hcount_sliding;
        end
        
        r_out_reg <= r_out;
        g_out_reg <= g_out;
        b_out_reg <= b_out;
        hsync_reg <= hsync;
        vsync_reg <= vsync;
        

    end
       
    wire [17:0] bram_sprite_adr;
    
    wire [7:0] bpm_number; // pass this into
    
    
    // BPM NUMBER
    assign bpm_number = hr_scaled; // SW[7:0] for manual testing
    
    wire bram_sprite_data;
 
    
    blk_mem_gen_0 sprite_memory_module(.clka(clk_100mhz), .addra(bram_sprite_adr), .douta(bram_sprite_data));

    

    wire display_mf;
    assign display_mf = SW[14];
    main_display xvga_display(.clk_100mhz(clk_100mhz), .clk_65mhz(clk_65mhz), .clk_1hz(clk_1hz), .system_status(system_status), .hcount(hcount),.vcount(vcount),
        .bram_sprite_adr(bram_sprite_adr), .bram_sprite_data(bram_sprite_data),
        .number(bpm_number),
        .at_display_area(at_display_area),
        .signal_in(doutb_lp),
        .display_mf(display_mf),
        .signal_mf(doutb_mf),
        .signal_pix(v_val),
        .signal_pix2(v_val2),
        .in_region(in_region),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out));      
          

          
    assign VGA_R = !blank ? r_out_reg : 3'b0; 
    assign VGA_G = !blank ? g_out_reg : 3'b0;
    assign VGA_B = !blank ? b_out_reg : 3'b0;
    assign VGA_HS = ~hsync_reg;
    assign VGA_VS = ~vsync_reg;
    


// AUDIO
//////////////////////////////////////////////////////////////////////////////////
// create all objects related to PWM audio output

  wire [7:0] pwm_audio_sample_data;
  reg pwm_en;
  assign AUD_SD = pwm_en;
  
  // use unsigned 8 bit uncompressed WAV file!
  audio_PWM audio_PWM_module(.clk(clk_100mhz), .reset(master_reset),
        .music_data(pwm_audio_sample_data), .PWM_out(AUD_PWM));


  reg [7:0] number_map_input_number;
  wire [7:0] number_map_output_number;
  wire [31:0] number_map_start_adr;
  wire [31:0] number_map_stop_adr;

  audio_number_map audio_number_map_module(.clk(clk_100mhz), .reset(master_reset),
        .number(number_map_input_number), .out_number(number_map_output_number),
        .start_adr(number_map_start_adr), .stop_adr(number_map_stop_adr));




// SD CARD
//////////////////////////////////////////////////////////////////////////////////
// SD card objects

  // general SD signals
  reg sd_rd; // when ready is high, asserting rd will begin a read
  wire sd_wr = 0;
  wire sd_ready;
  wire [4:0] sd_state; // for debug purposes
  
  // set SPI mode
  assign SD_DAT[2] = 1;
  assign SD_DAT[1] = 1;
  assign SD_RESET = 0;
    
  // read SD signals
  reg [31:0] sd_adr; // address of read operation
  wire [7:0] sd_dout; // data output for read operation
  wire sd_byte_available; // signal that a new byte has been presented on dout
  
  // write SD signals
  wire [7:0] sd_din = 0;
  wire sd_ready_for_next_byte = 0;
  
  
  sd_controller sd_controller_module(.cs(SD_DAT[3]), .mosi(SD_CMD), .miso(SD_DAT[0]),
        .sclk(SD_SCK), .rd(sd_rd), .wr(sd_wr), .reset(master_reset),
        .din(sd_din), .dout(sd_dout), .byte_available(sd_byte_available),
        .ready(sd_ready), .address(sd_adr), .clk(clk_25mhz), 
        .ready_for_next_byte(sd_ready_for_next_byte), .status(sd_state));



  reg fifo_wr_en;
  reg fifo_rd_en;
  
  wire [7:0] fifo_dout;
  assign fifo_dout = pwm_audio_sample_data;
  
  wire [7:0] fifo_din;
  assign fifo_din = sd_dout;

  wire fifo_full;
  wire fifo_empty;
  wire fifo_almost_empty;
  wire [13:0] fifo_count;
  

  fifo_generator_0 audio_sample_buffer(.clk(clk_100mhz), .rst(master_reset), .din(fifo_din), .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en), .dout(fifo_dout), .full(fifo_full), .empty(fifo_empty),
        .data_count(fifo_count));





// UI FSM + AUDIO PLAYBACK LOGIC
//////////////////////////////////////////////////////////////////////////////////


  // Reg definitions
  reg last_clk_32khz;
  reg last_clk_1hz;
  reg last_clk_point_2hz;
  reg last_system_status;

  reg last_btn_up;
  reg last_btn_down;
  reg last_btn_center;
  reg last_btn_left;
  reg last_btn_right;

  reg last_sd_byte_available;
  reg [5:0] read_counter;
  reg [31:0] sample_increment;

  reg last_audio_playing;
  reg [3:0] audio_number_loop_count;
  reg audio_number_loop_playing;
  reg audio_playing_done;
  reg audio_playing;
  reg [15:0] exit_count;
  reg [15:0] audio_beep_counter;
  
  // SD module playback parameters
  // Addresses must be multiple of 512 (i.e., end in hex 200,400,600,800,a00,c00,e00)
  reg [31:0] sd_start_adr = 'hcd_000;
  reg [31:0] sd_stop_adr = 'h100_000;
  reg [31:0] internal_sd_stop_adr;

  reg [15:0] boot_counter;

 
  always @ (posedge clk_100mhz) begin
      
    
      if (master_reset) begin
          read_counter <= 0;
          sd_rd <= 0;
          fifo_rd_en <= 0;
          audio_playing <= 0;
          sd_adr <= 'hcd_000;
          sd_start_adr <= 'hcd_000;
          sd_stop_adr <= 'h100_000;
          LED16_R <= 1;
          LED16_G <= 0;
          LED16_B <= 0;
          LED17_R <= 0;
          LED17_G <= 0;
          LED17_B <= 0;
          system_status <= 3;
      end else if (master_halt) begin
  
          // do nothing, keep 7 segment displayed for SD read address
      
      end else begin
        
                 
            
            // state machine check
              if (system_status == 3) begin // boot state
                  
                  
                  // wait for SD card to initialize, then play tone when ready
                  if (clk_1hz == 1 && last_clk_1hz == 0) begin
                      boot_counter <= boot_counter + 1;
                  end
                  
                  if (boot_counter == 0) begin
                      sd_start_adr <= 'hcd_000;
                      sd_stop_adr <= 'h100_000;
                      audio_playing <= 1;
                  end else if (boot_counter == 2) begin
                      
                  end else if (boot_counter >= 3) begin
                      system_status <= 1;
                      boot_counter <= 0;
                  end

              end else if (last_btn_down == 0 && btn_down == 1) begin // btn down => run mode

                  system_status <= 1;
              
              end else if (last_btn_left == 0 && btn_left == 1) begin // btn left <= pause mode
              
                  system_status <= 0;
              
              end else if (last_btn_up == 0 && btn_up == 1) begin // btn up <= error mode
                  
                  system_status <= 2;
                  sd_start_adr <= 'hbf_a00;
                  sd_stop_adr <= 'hcc_000;
                  audio_playing <= 1;
                  
                  
              end else if (system_status == 2) begin // error

                  // handled in display module

              end else if (system_status == 0) begin // paused

                  // handled in display module
              
              end else begin
                  system_status <= 1;
                  LED16_R <= 0;
                

                    // play windows startup tone
                    if (last_btn_right == 0 && btn_right == 1) begin
                        sd_start_adr <= 'hcd_000;
                        sd_stop_adr <= 'h100_000;
                        audio_playing <= 1;
                    end
    
                    // play number from switch
                    if (last_btn_center == 0 && btn_center == 1) begin
                        audio_number_loop_playing <= 1;
                    end
    

                    // automatic audio announcer feature
                    if (last_clk_point_2hz == 0 && clk_point_2hz == 1 && audio_playing == 0) begin
                        audio_number_loop_playing <= 1;
                    end else begin
                    
                        // play peak beep noise if user setting configured and it won't interrupt the announcer
                        if (peak == 1 && SW[9]) begin
                        
                            // beeps will not overtake announcement
                            if (audio_playing == 0) begin
                                audio_beep_counter <= 1;
                            end
                            
                        //    flatline sound
                        //    sd_start_adr <= 'h114_e00;
                        //    sd_stop_adr <= 'h150_e00;
    
                        end
                    
                    end
                    
                    
                    if (audio_beep_counter == 1) begin
                            //    // beep
                            sd_start_adr <= 'h111_600;
                            sd_stop_adr <= 'h114_e00;
                            audio_playing <= 1;
                            audio_beep_counter <= 0;
                    end
    
    
                    end // state machine check
    
    
    
        // btn press history used for btn edge triggers
         last_btn_up <= btn_up;
         last_btn_down <= btn_down;
         last_btn_center <= btn_center;
         last_btn_left <= btn_left;
         last_btn_right <= btn_right;
        
        // misc edge triggers
        last_audio_playing <= audio_playing;
        last_sd_byte_available <= sd_byte_available;
        last_clk_32khz <= clk_32khz;
        last_clk_1hz <= clk_1hz;
        last_clk_point_2hz <= clk_point_2hz;
        last_system_status <= system_status;
    




        // KNOWN BUG:
        // FIRST SAMPLE PLAYED MIGHT BUZZ AT START
        // Possible fix is to check sample fifo buffer and make sure it contains real audio data, not just buzz
    
    
        /// WORKING CODE TO PLAY NUMBER LOOP
    
        if (audio_number_loop_playing == 1) begin
        
           // check if number is zero after playing, play beats per minute
           if (number_map_input_number == 0 && audio_number_loop_count > 0) begin
                 audio_number_loop_playing <= 0;
                 audio_number_loop_count <= 0;
           end
    
           // init number from switches, load first adrs
           else if (audio_number_loop_count == 0) begin
                 number_map_input_number <= bpm_number;
                 audio_playing <= 1;
                 sd_start_adr <= number_map_start_adr;
                 sd_stop_adr <= number_map_stop_adr;
                audio_number_loop_count <= audio_number_loop_count + 1;
            end
    
            // play first number
            else if (audio_number_loop_count == 1) begin
                 audio_playing <= 1;
                 sd_start_adr <= number_map_start_adr;
                 sd_stop_adr <= number_map_stop_adr;
                audio_number_loop_count <= audio_number_loop_count + 1;        
            end
            
            // play next numbers
            else if (audio_number_loop_count > 1 && audio_playing_done == 1) begin
                number_map_input_number <= number_map_output_number;
                sd_start_adr <= number_map_start_adr;
                 sd_stop_adr <= number_map_stop_adr;
                 audio_playing <= 1;
                 audio_number_loop_count <= audio_number_loop_count + 1;
            end
           
            // if number is zero before playing, quit
            else if (number_map_input_number == 0) begin
                audio_number_loop_playing <= 0;
                audio_number_loop_count <= 0;
            end
    
                      
        end
        
        
    
    
         // WORKING CODE FOR AUDIO PLAYBACK
         // provide sd_start_addr, sd_stop_addr, audio_playing
    
        // sd_byte_available can trigger high multiple cycles for one byte
        // we use this to ensure a positive clock edge
        // do not use fifo_wr_en <= sd_byte_available
        if (last_sd_byte_available == 0 && sd_byte_available == 1) begin
              fifo_wr_en <= 1;
        end else begin
              fifo_wr_en <= 0;
        end
    
    
          if (audio_playing) begin
          
             // load correct start address if beginning playback
             if (last_audio_playing == 0) begin
                sd_adr <= sd_start_adr;
                internal_sd_stop_adr <= sd_stop_adr;
                pwm_en <= 1;
             end
             
             else begin
                      
                  // load samples from SD
                 if (fifo_count < 'd50 && sd_adr <= internal_sd_stop_adr) begin // fifo_count < 'd50
                     sd_rd <= 1;
                 end else begin
                     sd_rd <= 0;
                 end
              
                  // read samples from FIFO
                  if (clk_32khz == 1 && last_clk_32khz == 0 && fifo_empty == 0) begin
                      fifo_rd_en <= 1; // will output a new sample on fifo_dout
                      sample_increment <= sample_increment + 1;
                  end else begin
                      fifo_rd_en <= 0;
                  end
                  
                  // used for continuous playback
                  if (sample_increment >= 511) begin
                     sd_adr <= sd_adr + 32'h200;
                     sample_increment <= 0;
                  end
                  
                  if (sd_adr >= internal_sd_stop_adr && last_audio_playing == 1) begin // not the best way to do this! but it works. in future use conditional fifo_empty check
                    pwm_en <= 0;
                    audio_playing <= 0;
                    audio_playing_done <= 1;
                  end
    
              end
    
          end else begin
    
                sd_adr <= 0;
                pwm_en <= 0;
                audio_playing_done <= 0;
    
          end // audio_playing
    
    
    
    
      end // reset check
    end // always @
    
    
    
    
    endmodule



