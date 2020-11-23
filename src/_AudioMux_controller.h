/*
 * _AudioMux_controller.h
 *
 *  Created on: 27. mai 2020
 *      Author: teig
 */


#ifndef AUDIOMUX_CONTROLLER_H_
#define AUDIOMUX_CONTROLLER_H_

[[combinable]]
void buttons_client_task (
        client i2c_internal_commands_if if_i2c_internal_commands,
        client i2c_general_commands_if  if_i2c_general_commands,
        server button_if_gen            i_buttons_in[BUTTONS_NUM_CLIENTS],
        out port                        p_display_notReset,
        client softblinker_if           if_softblinker);

#endif /* AUDIOMUX_CONTROLLER_H_ */
