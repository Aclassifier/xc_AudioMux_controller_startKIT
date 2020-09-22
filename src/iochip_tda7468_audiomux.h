/*
 * iochip_tda7468_audiomux.h
 *
 *  Created on: 3. june 2020
 *      Author: teig *
 */

#ifndef IOCHIP_TDA7468_AUDIO_MUX_H_
#define IOCHIP_TDA7468_AUDIO_MUX_H_

// AudioMUX by MikroElektronica,
//     see https://www.mikroe.com/audiomux-click
// TDA7468 TWO BANDS DIGITALLY CONTROLLED AUDIO PROCESSOR WITH BASS ALC SURROUND by ST,
//     see https://download.mikroe.com/documents/datasheets/TDA7468.pdf
// MY BLOG NOTE, WITH PAGE 6 OF DATA SHEET ANNOTATED
//     https://www.teigfam.net/oyvind/home/technology/208-my-processor-to-analogue-audio-equaliser-notes/#tda7468_i2c_chip
// Some important things to be aware of
//     1. Observe that TDA7468 cannot be read from, only written to (R/W=BIT0 of the "address byte" is always 0)
//     2. Therefore the "address" is not 0x88 but I2C_ADDRESS_OF_AUDIOMUX is (0x88>>1)=0x44 (seen as a 7-bits address)
//     3. The AudioMUX does not have the surround sound wiring (pin 7->8 and 22->21) wired,
//        but the TDA7468_R2_SURROUND bits DATA_SURROUND_MIXING_MASK _must_ still be set correctly!

typedef enum i2c_reg_addr_audio_mux_tda7468_e {
    TDA7468_R0_INPUT_SELECT_AND_MIC = 0,
    TDA7468_R1_INPUT_GAIN           = 1,
    TDA7468_R2_SURROUND             = 2,
    TDA7468_R3_VOLUME_LEFT          = 3,
    TDA7468_R4_VOLUME_RIGHT         = 4,
    TDA7468_R5_TREBLE_AND_BASS      = 5,
    TDA7468_R7_OUTPUT_MUTE          = 6,
    TDA7468_R7_BASS_ALC             = 7,
    //
    TDA7468_NUM_REGS = 8
} i2c_reg_addr_audio_mux_tda7468_e;

#define LEN_I2C_TDA7468_MAX_BYTES (LEN_I2C_SUBADDRESS + TDA7468_NUM_REGS) // Not including device address i2c_dev_address_internal_e

#define TDA7468_REG_ADDR_AUTOINCREMENT_MASK 0x10

#define POWER_ON_RESET_CONDITION_ALL_REGISTERS 0xfe // Only BIT0 is 0. Datasheet TDA7468 page 9

// If this bit is set then repeated
//     DATA after ADDRESS, REG_ADDR (like 1), DATA (FOR 1),
//         DATA (FOR 2),
//         DATA (FOR 3) ,
//         etc. up to max 7 and then to 0
//
#define TDA7468_REG_ADDR_INCREMENTAL_BUS_BIT 0x10 // BIT5 of i2c_reg_addr_audio_mux_tda7468_e

// TDA7468_R0_INPUT_SELECT_AND_MIC
//
#define DATA_INPUT_SELECT_IN_1_4_MASK   0x03
#define DATA_INPUT_SELECT_IN5_MUTE_MASK 0x04
#define DATA_INPUT_SELECT_MIC_GAIN_MASK 0x38
#define DATA_INPUT_SELECT_MIC_OFF_MASK  0x20
//
#define DATA_INPUT_SELECT_IN1_VAL               (0 << 0)
#define DATA_INPUT_SELECT_IN2_VAL               (1 << 0)
#define DATA_INPUT_SELECT_IN3_VAL               (2 << 0)
#define DATA_INPUT_SELECT_IN4_VAL               (3 << 0)
#define DATA_INPUT_SELECT_MUTE_ON_SOUND_OFF_VAL (1 << 2) // Opposite bitvalue to DATA_OUTPUT_MUTE_ON_SOUND_OFF_VAL
#define DATA_INPUT_SELECT_MUTE_OFF_SOUND_ON_VAL (0 << 2) // Opposite bitvalue to DATA_OUTPUT_MUTE_OFF_SOUND_ON_VAL
#define DATA_INPUT_SELECT_MIC_GAIN_14DB_VAL     (0 << 3)
#define DATA_INPUT_SELECT_MIC_GAIN_10DB_VAL     (1 << 3)
#define DATA_INPUT_SELECT_MIC_GAIN_06DB_VAL     (2 << 3)
#define DATA_INPUT_SELECT_MIC_GAIN_00DB_VAL     (3 << 3)
#define DATA_INPUT_SELECT_MIC_OFF_VAL           (1 << 5)

// TDA7468_R1_INPUT_GAIN
// No _MASK needed
//
#define DATA_INPUT_GAIN_00_DB_VAL (0 << 0)
#define DATA_INPUT_GAIN_02_DB_VAL (1 << 0)
#define DATA_INPUT_GAIN_04_DB_VAL (2 << 0)
#define DATA_INPUT_GAIN_06_DB_VAL (3 << 0)
#define DATA_INPUT_GAIN_08_DB_VAL (4 << 0)
#define DATA_INPUT_GAIN_10_DB_VAL (5 << 0)
#define DATA_INPUT_GAIN_12_DB_VAL (6 << 0)
#define DATA_INPUT_GAIN_14_DB_VAL (7 << 0)
//
#define DATA_INPUT_GAIN_02_DB_STEPS_FACTOR 2 // DATA_INPUT_GAIN_12_DB_VAL = (2 * 6)

// TDA7468_R2_SURROUND
// [BIT2..BIT0] -> NOT USED BITS
//     Observe that the AudioMUX has no connection for surround mixing, no connection between MUX-R and IS-R
//     and not between MUX-L and IS-L. Turning it off and on and setting the gain therefore have no effect.
//     The values below than then have no effect are named _NC_ for Not Connected.
//     These are [BIT2..BIT0] and they may be set to any value, they have no effect
//
#define DATA_SURROUND_NC_ON_MASK    0x01
#define DATA_SURROUND_NC_GAIN_MASK  0x06 // Not "buffer gain" (see below)
#define DATA_SURROUND_NC_BITS_MASK  (DATA_SURROUND_NC_ON_MASK bitor DATA_SURROUND_NC_GAIN_MASK)
#define DATA_SURROUND_NC_BITS_VALUE 0x00
//
// TDA7468_R2_SURROUND
// [BIT5..BIT4] -> STILL NEEDED TO CONFIGURE BITS
//     The chip still has a mixer that needs to be configured, plus a single 0dB/6dB buffer gain bit
//
#define DATA_SURROUND_MIXING_MASK                  0x38
#define DATA_SURROUND_MIXING_INVERTING_100PRO     (0 << 3) // Silent (since no MUX-L/IS-L or MUX-R/IS-R connection)
#define DATA_SURROUND_MIXING_INVERTING_50PRO      (1 << 3) // Some
#define DATA_SURROUND_MIXING_INVERTING_25PRO      (2 << 3) // More
#define DATA_SURROUND_MIXING_0PRO                 (3 << 3) // Full = MOST. USE THIS FOR THE AudioMUX board
#define DATA_SURROUND_MIXING_NON_INVERTING_100PRO (4 << 3) // Silent
#define DATA_SURROUND_MIXING_NON_INVERTING_75PRO  (5 << 3) // Some
#define DATA_SURROUND_MIXING_NON_INVERTING_50PRO  (6 << 3) // More
#define DATA_SURROUND_MIXING_MUTE                 (7 << 3) // Muted
//
// [BIT6]
//     Internal buffer (in the TDA7468 diagram they are before MUX-R and MUX-L outputs, with no text
//     But I have texted them in my annotaed diagram (ref. above)
//
#define DATA_SURROUND_BUFFER_GAIN_0DB_BIT_POS 6 // (1 << 6) is 0dB, zero is +6dB

// TDA7468_R3_VOLUME_LEFT and TDA7468_R4_VOLUME_RIGHT
//
// MASKS not needed since only setting value and or'ing
#define VOLUME1_1DB_STEPS_BIT_POS 0 // BIT0,BIT1,BIT2
#define VOLUME1_8DB_STEPS_BIT_POS 3 // BIT3,BIT4,BIT5
#define VOLUME2_8DB_STEPS_BIT_POS 6 // BIT6,BIT7

// int8_t from <stdint.h>
typedef int8_t  volume_dB_t; // Using dB values instead of the numerical typical [0..7] for coding readability
//              volume_dB_t int8_t  sizeof this is 1*88*3 =  264 bytes
//              volume_dB_t signed  sizeof this is 4*88*3 = 1056 bytes, saves 88*1 = 792 bytes
typedef int8_t  tone_dB_t;
typedef uint8_t bitfield_value_t;

#define NUM_VOLUME_SETTINGS             88
#define NUM_VOLUME_TABLES                3
#define     IOF_VOLUME1_1DB_STEPS_TABLE  0
#define     IOF_VOLUME1_8DB_STEPS_TABLE  1
#define     IOF_VOLUME2_8DB_STEPS_TABLE  2

#define VOLUME_STEP_DB 1
#define VOLUME_MAX_DB  0
#define VOLUME_MIN_DB  (-(NUM_VOLUME_SETTINGS-1)) // -87 dB

#define USING_VOLUME_SETTING_X 2 // 1 or 2

// USAGE: const volume_dB_t volume_dB_table [NUM_VOLUME_SETTINGS][NUM_VOLUME_TABLES] = { VOLUME_SETTING_TABLE_INIT };

#if (USING_VOLUME_SETTING_X==1)
    #define VOLUME_SETTING_1_INCREASING_LINEAR \
        {0,  0,  0}, {-1,  0,  0}, {-2,  0,  0}, {-3,  0,  0}, {-4,  0,  0}, {-5,  0,  0}, {-6,  0,  0}, {-7,  0,  0}, /*   0 to  -7 */ \
        {0, -8,  0}, {-1, -8,  0}, {-2, -8,  0}, {-3, -8,  0}, {-4, -8,  0}, {-5, -8,  0}, {-6, -8,  0}, {-7, -8,  0}, /*  -8 to -15 */ \
        {0,-16,  0}, {-1,-16,  0}, {-2,-16,  0}, {-3,-16,  0}, {-4,-16,  0}, {-5,-16,  0}, {-6,-16,  0}, {-7,-16,  0}, /* -16 to -23 */ \
        {0,-24,  0}, {-1,-24,  0}, {-2,-24,  0}, {-3,-24,  0}, {-4,-24,  0}, {-5,-24,  0}, {-6,-24,  0}, {-7,-24,  0}, /* -24 to -31 */ \
        {0,-32,  0}, {-1,-32,  0}, {-2,-32,  0}, {-3,-32,  0}, {-4,-32,  0}, {-5,-32,  0}, {-6,-32,  0}, {-7,-32,  0}, /* -32 to -39 */ \
        {0,-40,  0}, {-1,-40,  0}, {-2,-40,  0}, {-3,-40,  0}, {-4,-40,  0}, {-5,-40,  0}, {-6,-40,  0}, {-7,-40,  0}, /* -40 to -47 */ \
        {0,-48,  0}, {-1,-48,  0}, {-2,-48,  0}, {-3,-48,  0}, {-4,-48,  0}, {-5,-48,  0}, {-6,-48,  0}, {-7,-48,  0}, /* -48 to -55 */ \
        {0,-56,  0}, {-1,-56,  0}, {-2,-56,  0}, {-3,-56,  0}, {-4,-56,  0}, {-5,-56,  0}, {-6,-56,  0}, {-7,-56,  0}, /* -56 to -63 */ \
        {0,-56, -8}, {-1,-56, -8}, {-2,-56, -8}, {-3,-56, -8}, {-4,-56, -8}, {-5,-56, -8}, {-6,-56, -8}, {-7,-56, -8}, /* -64 to -71 */ \
        {0,-56,-16}, {-1,-56,-16}, {-2,-56,-16}, {-3,-56,-16}, {-4,-56,-16}, {-5,-56,-16}, {-6,-56,-16}, {-7,-56,-16}, /* -72 to -79 */ \
        {0,-56,-24}, {-1,-56,-24}, {-2,-56,-24}, {-3,-56,-24}, {-4,-56,-24}, {-5,-56,-24}, {-6,-56,-24}, {-7,-56,-24}  /* -80 to -87 */

    #define VOLUME_SETTING_TABLE_INIT VOLUME_SETTING_1_INCREASING_LINEAR

#elif (USING_VOLUME_SETTING_X==2)
    #define VOLUME_SETTING_2_STEPPED_LINEAR \
        {0,  0,  0}, {-1,  0,  0}, {-2,  0,  0}, {-3,  0,  0}, {-4,  0,  0}, {-5,  0,  0}, {-6,  0,  0}, {-7,  0,  0}, /*   0 to  -7 */ \
        {0, -8,  0}, {-1, -8,  0}, {-2, -8,  0}, {-3, -8,  0}, {-4, -8,  0}, {-5, -8,  0}, {-6, -8,  0}, {-7, -8,  0}, /*  -8 to -15 */ \
        {0,-16,  0}, {-1,-16,  0}, {-2,-16,  0}, {-3,-16,  0}, {-4,-16,  0}, {-5,-16,  0}, {-6,-16,  0}, {-7,-16,  0}, /* -16 to -23 */ \
        {0,-16, -8}, {-1,-16, -8}, {-2,-16, -8}, {-3,-16, -8}, {-4,-16, -8}, {-5,-16, -8}, {-6,-16, -8}, {-7,-16, -8}, /* -24 to -31 */ \
        {0,-16,-16}, {-1,-16,-16}, {-2,-16,-16}, {-3,-16,-16}, {-4,-16,-16}, {-5,-16,-16}, {-6,-16,-16}, {-7,-16,-16}, /* -32 to -39 */ \
        {0,-16,-24}, {-1,-16,-24}, {-2,-16,-24}, {-3,-16,-24}, {-4,-16,-24}, {-5,-16,-24}, {-6,-16,-24}, {-7,-16,-24}, /* -40 to -47 */ \
        {0,-24,-24}, {-1,-24,-24}, {-2,-24,-24}, {-3,-24,-24}, {-4,-24,-24}, {-5,-24,-24}, {-6,-24,-24}, {-7,-24,-24}, /* -48 to -55 */ \
        {0,-32,-24}, {-1,-32,-24}, {-2,-32,-24}, {-3,-32,-24}, {-4,-32,-24}, {-5,-32,-24}, {-6,-32,-24}, {-7,-32,-24}, /* -56 to -63 */ \
        {0,-40,-24}, {-1,-40,-24}, {-2,-40,-24}, {-3,-40,-24}, {-4,-40,-24}, {-5,-40,-24}, {-6,-40,-24}, {-7,-40,-24}, /* -64 to -71 */ \
        {0,-48,-24}, {-1,-48,-24}, {-2,-48,-24}, {-3,-48,-24}, {-4,-48,-24}, {-5,-48,-24}, {-6,-48,-24}, {-7,-48,-24}, /* -72 to -79 */ \
        {0,-56,-24}, {-1,-56,-24}, {-2,-56,-24}, {-3,-56,-24}, {-4,-56,-24}, {-5,-56,-24}, {-6,-56,-24}, {-7,-56,-24}  /* -80 to -87 */

    #define VOLUME_SETTING_TABLE_INIT VOLUME_SETTING_2_STEPPED_LINEAR
#else
    #error
#endif

typedef volume_dB_t volume_db_triplets_t [NUM_VOLUME_TABLES];
typedef volume_dB_t volume_dB_table_t    [NUM_VOLUME_SETTINGS][NUM_VOLUME_TABLES];

// TDA7468_R5_TREBLE_AND_BASS
//
#define TONE_TREBLE_BITPOS  0
#define TONE_BASS_BITPOS    4
#define TONE_STEP_DB        2
#define TONE_MAX_DB        14
#define TONE_MIN_DB      (-14)

// TDA7468_OUTPUT
#define DATA_OUTPUT_MUTE_MASK              0x01
#define DATA_OUTPUT_MUTE_ON_SOUND_OFF_VAL (0 << 0) // Opposite bitvalue to DATA_INPUT_SELECT_MUTE_ON_SOUND_OFF_VAL
#define DATA_OUTPUT_MUTE_OFF_SOUND_ON_VAL (1 << 0) // Opposite bitvalue to DATA_INPUT_SELECT_MUTE_OFF_SOUND_ON_VAL

// TDA7468_R7_BASS_ALC
// Not used


// FUNCTIONS

bitfield_value_t tda7468_make_volume (
        const volume_dB_t       volume_dB, // 0 to -87 dB
        const volume_dB_table_t volume_dB_table);

bitfield_value_t tda7468_make_tone (
        const tone_dB_t bass_dB,
        const tone_dB_t treble_dB);

bitfield_value_t tda7468_make_surround (
        const bool volume_buffer_gain_6_dB);

#else
    #error Nested include IOCHIP_TDA7468_AUDIO_MUX_H_
#endif



