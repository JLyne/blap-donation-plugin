void ScheduleDonationRequest(bool immediate = false) {
	if(gFallbackTimer != INVALID_HANDLE) {
		KillTimer(gFallbackTimer);
		gFallbackTimer = INVALID_HANDLE;
	}

	if(!gDonationsCvar.BoolValue) {
		return;
	}

	#if defined _DEBUG
		LogMessage("HTTP: Scheduling donation request");
	#endif

	gFallbackTimer = CreateTimer(immediate ? 0.1 : 5.0, MakeDonationRequest);
}

public Action MakeDonationRequest(Handle timer, any data) {
	#if defined _DEBUG
		LogMessage("HTTP: Making donation request");
	#endif

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, FALLBACK_URL);

	SteamWorks_SetHTTPCallbacks(request, OnTotalRequestCompleted);

	if(!SteamWorks_SendHTTPRequest(request)) {
		LogError("HTTP: Donation total HTTP request failed");
		ScheduleDonationRequest();
	}

	gFallbackTimer = INVALID_HANDLE;
	return Plugin_Stop;
}

public int OnTotalRequestCompleted(Handle request, bool failure, bool successful, EHTTPStatusCode eStatusCode) {
	ScheduleDonationRequest();

	if(!successful || eStatusCode != k_EHTTPStatusCode200OK) {
		LogError("Donation total HTTP request failed %d");

	} else {
		int size;

		SteamWorks_GetHTTPResponseBodySize(request, size);

		char[] sBody = new char[size];

		SteamWorks_GetHTTPResponseBodyData(request, sBody, size);

		int newTotal = ParseTotalJsonResponse(sBody);

		if(newTotal > 0 && newTotal != gDonationTotal) {
			#if defined _DEBUG
			LogMessage("HTTP: New total received %d", newTotal);
			#endif

			gPreviousDonationTotal = gDonationTotal;
			gDonationTotal = newTotal;
			UpdateDonationDisplays();
		}
	}

	CloseHandle(request);
}

public int ParseTotalJsonResponse(const char[] json) {
	Handle parsed = json_load(json);
	char total[16];

	if(parsed == INVALID_HANDLE) {
		LogError("HTTP: Invalid json (failed to parse)");

		return -1;
	}


	if(json_object_get_string(parsed, "grand_total", total, sizeof(total)) == -1) {
		LogError("HTTP: Invalid json (invalid total)");

		return -1;
	}

	ReplaceString(total, sizeof(total), "$", "");
	ReplaceString(total, sizeof(total), ",", "");

	CloseHandle(parsed);
	return RoundToFloor(StringToFloat(total));
}