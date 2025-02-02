// This is in it's own file cause of how goddamn monolithic this crap is.

/obj/machinery/airlock_controller/process()
	if(construction_state)
		return

	var/static/list/indexes = list("chamber_pressure", "exterior_pressure", "interior_pressure")
	for(var/memory_index in indexes)
		if(memory["[memory_index]_timestamp"] && memory["[memory_index]_timestamp"] + 5 SECONDS < world.time)
			memory -= "[memory_index]_timestamp"
			memory -= memory_index

	var/sensor_pressure = memory["chamber_pressure"]

	// Make sure the airlock can actually function in some way.
	if(isnull(sensor_pressure) && !memory["invalid"])
		post_signal(new /datum/signal(list(
			"tag" = interior_door_tag,
			"command" = "secure_close"
		)))
		post_signal(new /datum/signal(list(
			"tag" = exterior_door_tag,
			"command" = "secure_close"
		)))
		post_signal(new /datum/signal(list(
			"tag" = airpump_tag,
			"power" = FALSE,
			"sigtype" = "command"
		)))
		memory["invalid"] = TRUE
		return
	else if(memory["invalid"] && sensor_pressure)
		memory -= "invalid"
	else if(memory["invalid"])
		return

	switch(state)
		if(BULKHEAD_STATE_OPEN)
			// Turn off the pump, we're done here.
			if(memory["pump_status"] != "off")
				post_signal(new /datum/signal(list(
					"tag" = airpump_tag,
					"power" = FALSE,
					"sigtype" = "command"
				)))

			else if (target_state != BULKHEAD_STATE_OPEN)
				state = BULKHEAD_STATE_CLOSED

		if(BULKHEAD_STATE_INOPEN)
			if(target_state != BULKHEAD_STATE_INOPEN)
				if(memory["interior_status"] == "closed")
					state = BULKHEAD_STATE_CLOSED
				else
					post_signal(new /datum/signal(list(
						"tag" = interior_door_tag,
						"command" = "secure_close"
					)))
			else
				if(memory["pump_status"] != "off")
					post_signal(new /datum/signal(list(
						"tag" = airpump_tag,
						"power" = FALSE,
						"sigtype" = "command"
					)))

		if(BULKHEAD_STATE_PRESSURIZE)
			if(target_state == BULKHEAD_STATE_INOPEN || target_state == BULKHEAD_STATE_OPEN || target_state == BULKHEAD_STATE_OUTOPEN)
				var/is_safe = sensor_pressure >= ONE_ATMOSPHERE*0.95
				if(is_safe && target_state == BULKHEAD_STATE_INOPEN)
					if(memory["interior_status"] == "open")
						state = BULKHEAD_STATE_INOPEN
					else
						post_signal(new /datum/signal(list(
							"tag" = interior_door_tag,
							"command" = "secure_open"
						)))
				else if(is_safe && target_state == BULKHEAD_STATE_OPEN)
					if(memory["interior_status"] == "open" && memory["exterior_status"] == "open")
						state = BULKHEAD_STATE_OPEN
					else
						post_signal(new /datum/signal(list(
							"tag" = interior_door_tag,
							"command" = "secure_open"
						)))
						post_signal(new /datum/signal(list(
							"tag" = exterior_door_tag,
							"command" = "secure_open"
						)))
				else if(is_safe && target_state == BULKHEAD_STATE_OUTOPEN)
					if(memory["exterior_status"] == "open")
						state = BULKHEAD_STATE_OUTOPEN
					else
						post_signal(new /datum/signal(list(
							"tag" = exterior_door_tag,
							"command" = "secure_open"
						)))

				else
					var/datum/signal/signal = new(list(
						"tag" = airpump_tag,
						"sigtype" = "command"
					))
					if(memory["pump_status"] == "siphon")
						signal.data["stabilize"] = TRUE
					else if(memory["pump_status"] != "release")
						signal.data["power"] = TRUE
					post_signal(signal)
			else
				state = BULKHEAD_STATE_CLOSED

		if(BULKHEAD_STATE_CLOSED)
			if(memory["interior_status"] != "closed")
				post_signal(new /datum/signal(list(
					"tag" = interior_door_tag,
					"command" = "secure_close"
				)))
			if(memory["exterior_status"] != "closed")
				post_signal(new /datum/signal(list(
					"tag" = exterior_door_tag,
					"command" = "secure_close"
				)))

			if(target_state == BULKHEAD_STATE_OUTOPEN)
				if(!is_firelock && !docked)
					state = BULKHEAD_STATE_DEPRESSURIZE
				else
					state = BULKHEAD_STATE_PRESSURIZE

			else if(target_state == BULKHEAD_STATE_INOPEN || target_state == BULKHEAD_STATE_OPEN)
				state = BULKHEAD_STATE_PRESSURIZE

			else
				// Always have the pump on if the alarm's going, otherwise, turn it off, as normal use doesn't require hiding in here.
				if(is_firelock && sound_loop.is_active())
					var/datum/signal/signal = new(list(
						"tag" = airpump_tag,
						"sigtype" = "command"
					))
					if(memory["pump_status"] == "siphon")
						signal.data["stabilize"] = TRUE
					else if(memory["pump_status"] != "release")
						signal.data["power"] = TRUE
					post_signal(signal)

				else if(memory["pump_status"] != "off")
					post_signal(new /datum/signal(list(
						"tag" = airpump_tag,
						"power" = FALSE,
						"sigtype" = "command"
					)))

		if(BULKHEAD_STATE_DEPRESSURIZE)
			var/target_pressure = ONE_ATMOSPHERE*0.05
			if(!is_firelock)
				target_pressure = ONE_ATMOSPHERE*0.01

			if(sensor_pressure <= target_pressure)
				if(target_state == BULKHEAD_STATE_OUTOPEN)
					if(memory["exterior_status"] == "open")
						state = BULKHEAD_STATE_OUTOPEN
					else
						post_signal(new /datum/signal(list(
							"tag" = exterior_door_tag,
							"command" = "secure_open"
						)))
				else
					state = BULKHEAD_STATE_CLOSED
			else if((target_state != BULKHEAD_STATE_OUTOPEN) && is_firelock)
				state = BULKHEAD_STATE_CLOSED
			else
				var/datum/signal/signal = new(list(
					"tag" = airpump_tag,
					"sigtype" = "command"
				))
				if(memory["pump_status"] == "release")
					signal.data["purge"] = TRUE
				else if(memory["pump_status"] != "siphon")
					signal.data["power"] = TRUE
				post_signal(signal)

		if(BULKHEAD_STATE_OUTOPEN)
			if(target_state != BULKHEAD_STATE_OUTOPEN)
				if(memory["exterior_status"] == "closed")
					state = BULKHEAD_STATE_CLOSED
				else
					post_signal(new /datum/signal(list(
						"tag" = exterior_door_tag,
						"command" = "secure_close"
					)))
			else
				if(docked)
					if(memory["interior_lock_status"] != "unlocked")
						post_signal(new /datum/signal(list(
							"tag" = interior_door_tag,
							"command" = "unlock"
						)))
				else if(memory["exterior_status"] != "open")
					post_signal(new /datum/signal(list(
						"tag" = exterior_door_tag,
						"command" = "secure_open"
					)))
				// Stop the pump if it's on. It shouldn't be.
				if(memory["pump_status"] != "off")
					post_signal(new /datum/signal(list(
						"tag" = airpump_tag,
						"power" = FALSE,
						"sigtype" = "command"
					)))

	memory["processing"] = state != target_state

	return TRUE
