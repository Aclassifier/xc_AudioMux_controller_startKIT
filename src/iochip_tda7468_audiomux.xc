/*
 * iochip_tda7468_audiomux.xc
 *
 *  Created on: 7. juni 2020
 *      Author: teig
 */

#include <platform.h> // core
#include <stdio.h>    // printf
#include <stdint.h>   // uint8_t
#include <iso646.h>   // readability

#include "_globals.h"
#include "param.h"
#include "iochip_tda7468_audiomux.h"

// ---
// Control printing
// See https://stackoverflow.com/questions/1644868/define-macro-for-debug-printing-in-c
// ---

#define DEBUG_PRINT_TEST 0 // [0->1] code about [5,12] kB
#define debug_print(fmt, ...) do { if((DEBUG_PRINT_TEST==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)



// Internal function

bitfield_value_t volume_1dB_steps_to_bitfield_value (const volume_dB_t volume_dB) {
    bitfield_value_t bitfield_value = 0;

    switch (volume_dB) {
        case  0: { bitfield_value = 0; } break;
        case -1: { bitfield_value = 1; } break;
        case -2: { bitfield_value = 2; } break;
        case -3: { bitfield_value = 3; } break;
        case -4: { bitfield_value = 4; } break;
        case -5: { bitfield_value = 5; } break;
        case -6: { bitfield_value = 6; } break;
        case -7: { bitfield_value = 7; } break;
        // default: let the debugger crash on this
    }
    return bitfield_value;
}


// Internal function

bitfield_value_t volume_8dB_steps_to_bitfield_value (const volume_dB_t volume_dB) {
    bitfield_value_t bitfield_value = 0;

    switch (volume_dB) {
        case   0: { bitfield_value = 0; } break;
        case  -8: { bitfield_value = 1; } break;
        case -16: { bitfield_value = 2; } break;
        case -24: { bitfield_value = 3; } break;
        case -32: { bitfield_value = 4; } break;
        case -40: { bitfield_value = 5; } break;
        case -48: { bitfield_value = 6; } break;
        case -56: { bitfield_value = 7; } break;
        // default: let the debugger crash on this
    }
    return bitfield_value;
}


// Internal function

bitfield_value_t tone_2db_steps_to_bitfield_value (const tone_dB_t tone_dB) {
    bitfield_value_t bitfield_value = 0;

    switch (tone_dB) {
        case -14: { bitfield_value = 0x00; } break;
        case -12: { bitfield_value = 0x01; } break;
        case -10: { bitfield_value = 0x02; } break;
        case  -8: { bitfield_value = 0x03; } break;
        case  -6: { bitfield_value = 0x04; } break;
        case  -4: { bitfield_value = 0x05; } break;
        case  -2: { bitfield_value = 0x06; } break;
        case   0: { bitfield_value = 0x07; } break;
        case  14: { bitfield_value = 0x08; } break;
        case  12: { bitfield_value = 0x09; } break;
        case  10: { bitfield_value = 0x0a; } break;
        case   8: { bitfield_value = 0x0b; } break;
        case   6: { bitfield_value = 0x0c; } break;
        case   4: { bitfield_value = 0x0d; } break;
        case   2: { bitfield_value = 0x0e; } break;
        //     0: { bitfield_value = 0x0f; } break; // Not needed
        // default: let the debugger crash on this
    }
    return bitfield_value;
}


// External function

bitfield_value_t tda7468_make_volume (
        const volume_dB_t       volume_dB, // 0 to -87 dB
        const volume_dB_table_t volume_dB_table) {

    bitfield_value_t bitfield_value_return = 0;
    {
        bitfield_value_t bitfield_value_build;

        const unsigned index = abs(volume_dB);

        bitfield_value_build = volume_1dB_steps_to_bitfield_value (volume_dB_table[index][IOF_VOLUME1_1DB_STEPS_TABLE]); // 0 to -7 dB
        bitfield_value_return or_eq (bitfield_value_build << VOLUME1_1DB_STEPS_BIT_POS); // Into [BIT0-BIT2]

        bitfield_value_build = volume_8dB_steps_to_bitfield_value (volume_dB_table[index][IOF_VOLUME1_8DB_STEPS_TABLE]); // 0 to -56 dB
        bitfield_value_return or_eq (bitfield_value_build << VOLUME1_8DB_STEPS_BIT_POS); // Into [BIT3-BIT5]

        bitfield_value_build = volume_8dB_steps_to_bitfield_value (volume_dB_table[index][IOF_VOLUME2_8DB_STEPS_TABLE]); // 0 to -24 dB
        bitfield_value_return or_eq (bitfield_value_build << VOLUME2_8DB_STEPS_BIT_POS); // Into [BIT6-BIT7]
    }
    return bitfield_value_return;
}


// External function

bitfield_value_t tda7468_make_tone (
        const tone_dB_t bass_dB,
        const tone_dB_t treble_dB) {

    bitfield_value_t bitfield_value_return = 0;
    {
        bitfield_value_t bitfield_value_build;

        bitfield_value_build = tone_2db_steps_to_bitfield_value (bass_dB);
        bitfield_value_return or_eq (bitfield_value_build << TONE_BASS_BITPOS);

        bitfield_value_build = tone_2db_steps_to_bitfield_value (treble_dB);
        bitfield_value_return or_eq (bitfield_value_build << TONE_TREBLE_BITPOS);
    }
    return bitfield_value_return;
}

// External function

bitfield_value_t tda7468_make_surround (
        const bool volume_buffer_gain_6_dB) {

    bitfield_value_t bitfield_value_return =
            DATA_SURROUND_MIXING_0PRO bitor // THIS IS NECESSARRY, EVEN IF MUX-L/MUX-R are not connected to respective IS-L/IS-R!
            ((not volume_buffer_gain_6_dB) << DATA_SURROUND_BUFFER_GAIN_0DB_BIT_POS);

    return bitfield_value_return;
}
