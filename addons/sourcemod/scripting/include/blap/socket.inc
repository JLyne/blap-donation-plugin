void InitDonationSocket() {
	#if defined NO_SOCKET
	#if defined _DEBUG
	LogMessage("Socket: Sockets disabled, using HTTP");
	#endif
	ScheduleDonationRequest(true);
	#else

	if(gSocket[SSocket] != INVALID_HANDLE && SocketIsConnected(gSocket[SSocket])) {
		return;
	}

	//Cancel any fallback requests
	if(gFallbackTimer != INVALID_HANDLE) {
		KillTimer(gFallbackTimer);
		gFallbackTimer = INVALID_HANDLE;
	}

	#if defined _DEBUG
	LogMessage("Socket: Connecting");
	#endif
	
	gSocket[SAttempts]++;
	gSocket[SSocket] = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketConnect(gSocket[SSocket], OnSocketConnected, OnSocketReceive, OnSocketDisconnected, SOCKET_HOST, SOCKET_PORT);
	#endif
}

public Action RetryDonationSocket(Handle timer, any data) {
	//Fallback to HTTP if cannot connect repeatedly
	if(gSocket[SAttempts] == 3) {
		LogError("Socket: 3 failed attempts, falling back to HTTP for now.");
		ScheduleDonationRequest(true);
		gSocket[SAttempts] = 0;
		return;	
	}


	InitDonationSocket();
}

public int OnSocketConnected(Handle socket, any arg) {
	LogMessage("Socket: Connected");

	gSocket[SHeartbeatTimer] = CreateTimer(0.1, SendHeartbeat);
}

public int OnSocketError(Handle socket, const int errorType, const int errorNum, any arg) {
	LogError("Socket: Error %d %d", errorType, errorNum);
	
	KillSocketTimers();
	CloseHandle(socket);
	gSocket[SSocket] = INVALID_HANDLE;
	CreateTimer(3.0, RetryDonationSocket);
}

public int OnSocketReceive(Handle socket, const char[] receiveData, const int dataSize, any arg) {
	if(!strcmp(receiveData, "pong", false)) {
		KillSocketTimers();

		#if defined _DEBUG
		LogMessage("Socket: Heartbeat received");
		#endif

		gSocket[SHeartbeatTimer] = CreateTimer(5.0, SendHeartbeat);
		return;
	}

	Handle parsed = json_load(receiveData);
	char newTotal[16];
	int total;

	if(parsed == INVALID_HANDLE) {
		LogError("Socket: Invalid json (failed to parse)");
		return;
	}

	if(json_object_get_string(parsed, "newTotal", newTotal, sizeof(newTotal)) == -1) {
		LogError("Socket: Invalid json (invalid total)");
		CloseHandle(parsed);

		return;
	}

	CloseHandle(parsed);
	total = RoundToFloor(StringToFloat(newTotal));

	#if defined _DEBUG
	LogMessage("Socket: New total received %d", total);
	#endif

	if(total > gDonationTotal) {
		gSocket[SAttempts] = 0;
		gDonationTotal = total;
		UpdateDonationDisplays();
	}
}

public int OnSocketDisconnected(Handle socket, any arg) {
	#if defined _DEBUG
	LogMessage("Socket: Disconnected");
	#endif

	KillSocketTimers();
	CloseHandle(socket);
	gSocket[SSocket] = INVALID_HANDLE;
	CreateTimer(3.0, RetryDonationSocket);
}

public Action SendHeartbeat(Handle timer, any data) {
	KillSocketTimers();

	if(gSocket[SSocket] == INVALID_HANDLE || !SocketIsConnected(gSocket[SSocket])) {
		return;
	}

	#if defined _DEBUG
	LogMessage("Socket: Sending heartbeat");
	#endif

	SocketSend(gSocket[SSocket], "ping", 4);
	gSocket[STimeoutTimer] = CreateTimer(3.0, HearbeatTimeout);
}

public Action HearbeatTimeout(Handle timer, any data) {
	KillSocketTimers();

	if(gSocket[SSocket] == INVALID_HANDLE || !SocketIsConnected(gSocket[SSocket])) {
		return;
	}

	LogError("Socket: Heartbeat timed out. Reconnecting.");

	SocketDisconnect(gSocket[SSocket]);
	CreateTimer(1.0, RetryDonationSocket);
}

void KillSocketTimers() {
	if(gSocket[SHeartbeatTimer] != INVALID_HANDLE) {
		KillTimer(gSocket[SHeartbeatTimer]);
		gSocket[SHeartbeatTimer] = INVALID_HANDLE;
	}

	if(gSocket[STimeoutTimer] != INVALID_HANDLE) {
		KillTimer(gSocket[STimeoutTimer]);
		gSocket[STimeoutTimer] = INVALID_HANDLE;
	}
}