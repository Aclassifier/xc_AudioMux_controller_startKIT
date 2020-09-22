/*
 * i2c_client_task.h
 *
 *  Created on: 27. feb. 2015
 *      Author: Teig
 */

#ifndef I2C_ICLIENT_TASK_H_
#define I2C_ICLIENT_TASK_H_

#if (IS_MYTARGET==IS_MYTARGET_STARTKIT)

    typedef enum i2c_dev_address_internal_e {
        I2C_ADDRESS_OF_DISPLAY                        =  0x3C,    // UG-2832HSWEG02 with chip SSD1306 from Univision Technology Inc.
        I2C_ADDRESS_OF_AUDIOMUX                       = (0x88>>1) // AUDIOMUX CLICK from MikroElektronika with chip TDA7468D from ST
                                                                  // BIT0 is R/W and is not part of address. BIT0 is inserted by READ (to 1) or WRITE (to 0) type functions.
                                                                  // Therefore the data sheet is wrong when it says that the address is 0x88.
                                                                  // I2C has per def only 7-bits or 10-bits address. SO, THE TDA7468 IS ONLY EVER WRITTEN TO!
                                                                  // https://www.mikroe.com/audiomux-click
    } i2c_dev_address_internal_e; // i2c_dev_address_t

#elif (IS_MYTARGET==IS_MYTARGET_XCORE_200_EXPLORER)

    typedef enum i2c_dev_address_internal_e {
        I2C_ADDRESS_OF_ACCELEROMETER_AND_MAGNETOMETER = 0x1E, // FXOS8700CQ BMG160 3-axis gyroscope sensor
                                                              // NOT modifiable plus hardwired on XMOS XCORE-200 EXPLORERKIT
        I2C_ADDRESS_OF_DISPLAY                        = 0x3C, // UG-2832HSWEG02 with chip SSD1306 from Univision Technology Inc.
        I2C_ADDRESS_OF_GYROSCOPE_BMG160               = 0x68, // BMG160  FXOS8700CQ Digital Sensor - 3D Accelerometer (±2g/±4g/±8g) + 3D Magnetometer
                                                              // NOT modifiable plus hardwired on XMOS XCORE-200 EXPLORERKIT
                                                              // Observe that CHRONODOT has same address 0x68, also hard wired! So cannot coexist on same I2C bus
        I2C_ADDRESS_OF_PORT_EXPANDER                  = 0x20  // 0x20 Lines: 0  0  0 [0x20:000]->[0x27:111] MCP23008
    } i2c_dev_address_internal_e; // i2c_dev_address_t

#elif (IS_MYTARGET==IS_MYTARGET_XCORE_XA_MODULE)

    typedef enum i2c_dev_address_internal_e {
        I2C_ADDRESS_OF_DISPLAY                        =  0x3C,    // UG-2832HSWEG02 with chip SSD1306 from Univision Technology Inc.
        I2C_ADDRESS_OF_AUDIOMUX                       = (0x88>>1) // AUDIOMUX CLICK from MikroElektronika with chip TDA7468D from ST
                                                                  // BIT0 is R/W and is not part of address. BIT0 is inserted by READ (to 1) or WRITE (to 0) type functions.
                                                                  // Therefore the data sheet is wrong when it says that the address is 0x88.
                                                                  // I2C has per def only 7-bits or 10-bits address. SO, THE TDA7468 IS ONLY EVER WRITTEN TO!
                                                                  // https://www.mikroe.com/audiomux-click
    } i2c_dev_address_internal_e; // i2c_dev_address_t
#else
    #error TARGET NOT DEFINED
#endif

#define I2C_HARDWARE_NUM_BUSES  2
//
typedef enum i2c_hardware_iof_bus_t {
    I2C_HARDWARE_IOF_DISPLAY,
    I2C_HARDWARE_IOF_AUDIOMUX
} i2c_hardware_iof_bus_t;

#define I2C_HARDWARE_NUM_CLIENTS 1

typedef enum i2c_display_iof_client_e {
    I2C_DISPLAY_IOF_ICLIENT_0,
} i2c_display_iof_client_e;

typedef enum i2c_audiomux_iof_client_e {
    I2C_AUDIOMUX_IOF_ICLIENT_0,
} i2c_audiomux_iof_client_e;

#define LEN_I2C_SUBADDRESS 1 // Most often some register address after the device address i2c_dev_address_internal_e
#define IOF_I2C_SUBADDRESS 0
typedef uint8_t i2c_uint8_t;

typedef interface i2c_general_commands_if {

    bool write_reg_ok (
            const i2c_hardware_iof_bus_t i2c_hardware_iof_bus,
            const i2c_dev_address_t      dev_addr,
            const i2c_uint8_t            i2c_bytes[], // reg_addr followed by data
            const static unsigned        nbytes); // must include space for LEN_I2C_SUBADDRESS

    bool read_reg_ok (
            const i2c_hardware_iof_bus_t i2c_hardware_iof_bus,
            const i2c_dev_address_t      dev_addr,
            const i2c_uint8_t            reg_addr,
                  uint8_t                &the_register);

} i2c_general_commands_if;

typedef interface i2c_internal_commands_if {

    bool write_display_ok (
            const i2c_hardware_iof_bus_t i2c_hardware_iof_bus,
            const i2c_dev_address_t      dev_addr,
            const i2c_reg_address_t      reg_addr,
            const unsigned char          data[],
            const unsigned               nbytes);

} i2c_internal_commands_if;

#define I2C_INTERNAL_NUM_CLIENTS 1
#define I2C_GENERAL_NUM_CLIENTS  1


[[combinable]]
void I2C_Client_Task (
        server i2c_internal_commands_if if_i2c_internal_commands[I2C_INTERNAL_NUM_CLIENTS],
        server i2c_general_commands_if  if_i2c_general_commands [I2C_GENERAL_NUM_CLIENTS],
        client i2c_master_if            if_i2c[I2C_HARDWARE_NUM_BUSES][I2C_HARDWARE_NUM_CLIENTS]); // synchronous

#else
    #error Nested include I2C_ICLIENT_TASK_H_
#endif

