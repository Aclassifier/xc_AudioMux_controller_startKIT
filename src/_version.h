/*
 * _version.h
 *
 *  Created on: 15. aug. 2018
 *      Author: teig
 */

#ifndef VERSION_H_
#define VERSION_H_

// SHOULD THE LENGTH OF THESE NEED TO CHANGE THEN THE STRING THEY ARE COPIED INTO MUST BE MODIFIED
//
#define XTIMECOMPOSER_VERSION_STR "14.4.1"

#define AUDIOMUX_VERSION_STR "1.2.01" // x.y.zz
#define AUDIOMUX_VERSION_NUM    1201

// 1201     12Apr2021           Same version number. Just tested with MIC_ARRAY to see if I could get the display up
// 1201     10Apr2021           read_reg_ok coded better, even if not used. No change in code
//                              Constraints: C:8/4 T:10/4 C:32/7 M:27348 S:3808 C:20050 D:3490
// 1200     10Apr2021 AMUX=012  Bass/treble etc. per input
//                              Constraints: C:8/4 T:10/4 C:32/7 M:27364 S:3808 C:20066 D:3490
// 1109     08dec2020           my_script.xta added
// 1108     25Nov2020 AMUX=011  Button_Task_4 is new. Now also building with long_disabled
//                              Button_Task_4 Constraints: C:8/4 T:10/4 C:32/7 M:25672 S:2896 C:19286 D:3490
//                              i2c_master_async.xc:131:26: warning: argument 1 of `i2c_master_async_aux' slices interface preventing analysis of its parallel usage (the bound parameter is not `const') [-Wunusual-code]
// 1107     23Nov2020 AMUX=010  new. Button_Task_3 is new, with button_noisy_time_us measured. SCREEN_BUTTONS modified
// 1106     09Nov2020           Some more advanced "logging" of SCREEN_BUTTONS. Also screened the cables from the buttons (and display) in one cable
//                              I noticed button_edge_cnt_max only happened on IOF_BUTTON_LEFT (14), but the other buttons never seemed to pick up any EMC(?)
// 1105     07Nov2020 AMUX=009  Rewrote Button_Task to Button_Task_2 to withstand not only debounce, but also EMC (assumed to always be leaving line high BUTTON_RELEASED after EMC)
//                              USE_BUTTON_TASK_NUM = 2
//                              TEST_DISPLAY_ON_CNT removed, made standard with SCREEN_BUTTONS
// 1104     03Nov2020           Extending DEBOUNCE_TIMEOUT_MS from 50 to TEST_DEBOUNCE_TIMEOUT_MS 100. DID NOT HELP:
//                              Had extra display_on_cnt "by itself" to 11 in 60 hours
// 1103     02Nov2020           TEST_DISPLAY_ON_CNT since seems to go on by itself, EMC from fridge on keys?
//                              DEBOUNCE_TIMEOUT_MS = 50
//                              Had extra display_on_cnt "by itself" to 8 in 36 hours
// 1102     26Oct2020 AMUX=008  SCREEN_INPUT and button pressed for long into dark did not work like assumed
//                              Constraints: C:8/4 T:10/4 C:32/7 M:24504 S:2664 C:18446 D:3394
// 1101     25Oct2020 AMUX=007  New screen is SCREEN_INPUT, to change TDA7468 input channel IN1 (default), IN2, IN3 or IN4
//                              Constraints: C:8/4 T:10/4 C:32/7 M:24532 S:2664 C:18478 D:3394
// 1100     24Sep2020           New text in SCREEN_ABOUT and ticking version up a lot!
// 0201     24Sep2020 AMUX=006  softblinker_task PWM control done as in the new lib_pwm_softblinker (which as actually made starting off from _this_ code)
// 0200     22Sep2020           New project from _AudioMux_controller 0197 which was for the xCORE-XA Code Module.
//                              Dropping makefile TARGET = XCORE-XA-MODULE since I have not found any way to flash it.
//                              I had two vacant STARTKIT, using one of those instead.
//                              /src/arm/_AudioMux_controller removed. It seems like keeping the rest of the sources under src/xcore/ is ok (but I removed that level as well)
//                              makfile now XCORE_ARM_PROJECT = 0
//                              NEW startKIT mounted for the XCore-XA. This works
// 0197     09Jul2020           Constraints: C:8/4 T:10/4 C:32/7 M:23616 S:2664 C:17590 D:3362
//                              I had to press left buttons twice after normal timout and display to dark.
//                              ignore_left_button_release_no_wake_from_dark had been set unconditionally
// 0196     09Jul2020 AMUX=006  No phantom screen before left button held for long and display went dark. Now left button taken an released instead
// 0195     08Jul2020 AMUX=005  Last change stopped dark display on timeout!
// 0194     08Jul2020 AMUX=004  Left button in for 1.5 secs turns display dark
//          06Jul2020           Typos
// 0193     25Jun2020 AMUX=003  AMUX=001 finished!
// 0192               AMUX=002  Test limit of PWM_ONE_PERCENT_TICS for when the eyes can notice blinking. Changed from 1 kHz to 100 Hz
//          25Jun2020 AMUX=001  I discovered when I described the menu at
//                              https://www.teigfam.net/oyvind/home/technology/208-my-processor-to-analogue-audio-equaliser-notes/#the_menu
//                              that SCREEN_RESET inc/dec buttons were not behaving as I wanted them to. Now the center button (add) adds
//                              bass, not treble
// 0191     24Jun2020           I think everything works now! (Except xflash!)
//                              xTIMEcomposer 14.4.1 build result:
//                                  Constraint check for tile[0]:
//                                    Cores available:            8,   used:          4 .  OKAY
//                                    Timers available:          10,   used:          4 .  OKAY
//                                    Chanends available:        32,   used:          7 .  OKAY
//                                    Memory available:       65536,   used:      23336 .  OKAY
//                                      (Stack: 2652, Code: 17322, Data: 3362)
//                              IN THE FOLLOWING WRITTEN LIKE THIS:
//                                  Constraints: C:8/4 T:10/4 C:32/7 M:23336 S:2652 C:17322 D:3362
// 0190     23Jun2020           Settling on this with no param but PWM_PORT_PIN_SIGN in pwm_softblinker.h. This should be reported to XMOS,
//                              since I think it is a dependency error
// 0181     23Jun2020           This also works provided I touch pwm_softblinker.xc
// 0180     23Jun2020           This also works provided I touch pwm_softblinker.xc
// 0179     23Jun2020           This also works, but I have to force it to recompile pwm_softblinker.xc when I change port_pin_sign in par
// 0178     23Jun2020           PWM and softblinking new, this works with port_pin_sign_e as is now
//                    WEB       https://www.teigfam.net/oyvind/blog_notes/208/code/audiomux_controller.zip
// 0177     21Jun2020           ARM code now blinks on and off with 1:1000. Ready for export of code, ref. "xCORE-XA with ARM core (not) flashable?" at
//                              https://www.xcore.com/viewtopic.php?f=8&t=7941.
//                    LOG       LOG OF XFLASH TERMINAL WINDOW (macOS 10.13.6 High Sierra):
//                                 myMachine:~ teig$ /Applications/XMOS_xTIMEcomposer_Community_14.4.1/SetEnv.command
//                                 bash-3.2$ xflash /Users/teig/workspace/_AudioMux_controller/bin/_AudioMux_controller.xe
//                                 Error: F03122 No Arm Binary supplied, please use option --arm-binary
//                                 bash-3.2$ xflash /Users/teig/workspace/_AudioMux_controller/bin/_AudioMux_controller.xe --arm-binary /Users/teig/workspace/_AudioMux_controller/bin/_AudioMux_controller
//                                 Error: F03139 xCORE image is too big for the ARM flash partition
//                                 bash-3.2$
//          21Jun2020 WARNING   i2c_master_async.xc:126:26: warning: argument 1 of `i2c_master_async_aux' slices interface preventing analysis
//                                  of its parallel usage (the bound parameter is not `const') [-Wunusual-code]
//                              I have done nothing to try to fix this, since it's in XMOS library code. However, I do think there is a newer version
//                              of lib_i2c. It's been there all the time, but I wrote it down now since I'm making the code public
//                              22Sep2020: Added comment in i2c_master_asynch
// 0176     18Jun2020           audiomux_context.volume_buffer_gain_6_dB added. It works.
// 0175     17Jun2020           I think all screens are there plus all functionality!
// 0174     16Jun2020           Coded basics of tone
// 0173     16Jun2020           SCREEN_DARK works
// 0172     16Jun2020           Detail
// 0171     15Jun2020           Ikke 71 ennå.. Better modularity. Repeat with delay handled
// 0170     14Jun2020           70-årsdag! Now repeat also works. Only volume
// 0107     13Jun2020           Counting dB up and down works, and sound gets through!
// 0106     11Jun2020           Testing, not working yet
// 0105     08Jun2020           This version writes to audioMUX successfully for the first time. Observe address is not 0x88 but 0x44
// 0104     07Jun2020           iochip_tda7468_audiomux.h and iochip_tda7468_audiomux.xc added. In work
// 0103     28May2020           Display works, it prints "HALLO" for the first time!
// 0102     28May2020           Log "cnt 25 BUTTON=110" - it simply works. I2C no tested yet
// 0101     28May2020           XMOS_PRODUCT_BUG_31286_32474 with new number as #53656
// 0101     27May2020           Initial
// ....     28Jun2020  AMUX=001 To get xflash to work:
//                              XCORE-200-EXPLORER.xn (xTIMEcomposer 14.4.1)
//                              See https://www.teigfam.net/oyvind/home/technology/098-my-xmos-notes/#ticket_xflash_1441_of_xcore-200_explorer_board_warnings
//                                  <Device NodeId="0" Tile="0" Class="SQIFlash" Name="bootFlash" Type="S25LQ016B" PageSize="256" SectorSize="4096" NumPages="8192">
//                                  replaced with
//                                  <Device NodeId="0" Tile="0" Class="SQIFlash" Name="bootFlash" Type="S25LQ016B">

#endif /* VERSION_H_ */

