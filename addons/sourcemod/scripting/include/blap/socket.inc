void InitDonationSocket() {
	#if defined NO_SOCKET
	#if defined _DEBUG
	LogMessage("Socket: Sockets disabled, using HTTP");
	#endif
	ScheduleDonationRequest(true);
	#else

	if(gSocket.socket != INVALID_HANDLE && SocketIsConnected(gSocket.socket)) {
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
	
	gSocket.attempts++;
	gSocket.socket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketConnect(gSocket.socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, SOCKET_HOST, SOCKET_PORT);
	#endif
}

public Action RetryDonationSocket(Handle timer, any data) {
	//Fallback to HTTP if cannot connect repeatedly
	if(gSocket.attempts == 3) {
		LogError("Socket: 3 failed attempts, falling back to HTTP for now.");
		ScheduleDonationRequest(true);
		gSocket.attempts = 0;
		return;	
	}


	InitDonationSocket();
}

public int OnSocketConnected(Handle socket, any arg) {
	LogMessage("Socket: Connected");

	gSocket.heartbeatTimer = CreateTimer(0.1, SendHeartbeat);
}

public int OnSocketError(Handle socket, const int errorType, const int errorNum, any arg) {
	LogError("Socket: Error %d %d", errorType, errorNum);
	
	KillSocketTimers();
	CloseHandle(socket);
	gSocket.socket = INVALID_HANDLE;
	CreateTimer(3.0, RetryDonationSocket);
}

public int OnSocketReceive(Handle socket, const char[] receiveData, const int dataSize, any arg) {
	if(!strcmp(receiveData, "pong", false)) {
		KillSocketTimers();

		#if defined _DEBUG
		LogMessage("Socket: Heartbeat received");
		#endif

		gSocket.heartbeatTimer = CreateTimer(5.0, SendHeartbeat);
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
		gSocket.attempts = 0;
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
	gSocket.socket = INVALID_HANDLE;
	CreateTimer(3.0, RetryDonationSocket);
}

public Action SendHeartbeat(Handle timer, any data) {
	KillSocketTimers();

	if(gSocket.socket == INVALID_HANDLE || !SocketIsConnected(gSocket.socket)) {
		return;
	}

	#if defined _DEBUG
	LogMessage("Socket: Sending heartbeat");
	#endif

	SocketSend(gSocket.socket, "ping", 4);
	gSocket.timeoutTimer = CreateTimer(3.0, HearbeatTimeout);
}

public Action HearbeatTimeout(Handle timer, any data) {
	KillSocketTimers();

	if(gSocket.socket == INVALID_HANDLE || !SocketIsConnected(gSocket.socket)) {
		return;
	}

	LogError("Socket: Heartbeat timed out. Reconnecting.");

	SocketDisconnect(gSocket.socket);
	CreateTimer(1.0, RetryDonationSocket);
}

void KillSocketTimers() {
	if(gSocket.heartbeatTimer != INVALID_HANDLE) {
		KillTimer(gSocket.heartbeatTimer);
		gSocket.heartbeatTimer = INVALID_HANDLE;
	}

	if(gSocket.timeoutTimer != INVALID_HANDLE) {
		KillTimer(gSocket.timeoutTimer);
		gSocket.timeoutTimer = INVALID_HANDLE;
	}
}