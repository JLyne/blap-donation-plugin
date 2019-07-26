public void PrecacheAssets() {

	for (int i = 0; i < sizeof(g_sDucksModel); i++)
	{
		g_iDuckModelIndexes[i] = PrecacheModel(g_sDucksModel[i]);
		AddFileToDownloadsTable(g_sDucksModel[i]);
	}
	
	PrecacheSound(DUCK_PICKUP_SND);

	PrecacheModel("models/items/currencypack_large.mdl");
	PrecacheModel("models/blap19/coins/coin_gravel.mdl");
	PrecacheModel("models/blap19/coins/coin_bronze.mdl");
	PrecacheModel("models/blap19/coins/coin_silver.mdl");
	PrecacheModel("models/blap19/coins/coin_gold.mdl");

	PrecacheModel(HOLOGRAM_MODEL);
	PrecacheModel(COINS_MODEL);
	PrecacheModel(NOTES_MODEL);
	AddFileToDownloadsTable(HOLOGRAM_MODEL);
	AddFileToDownloadsTable(COINS_MODEL);
	AddFileToDownloadsTable(NOTES_MODEL);

	PrecacheGeneric("materials/blap19/numbers.vmt");
	PrecacheGeneric("materials/blap19/numbers.vtf");
	PrecacheGeneric("materials/blap19/numbers-comma.vmt");
	PrecacheGeneric("materials/blap19/numbers-comma.vtf");

	AddFileToDownloadsTable("materials/blap19/numbers.vmt");
	AddFileToDownloadsTable("materials/blap19/numbers.vtf");
	AddFileToDownloadsTable("materials/blap19/numbers-comma.vmt");
	AddFileToDownloadsTable("materials/blap19/numbers-comma.vtf");

	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_blue.vtf");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_blue.vmt");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_red.vtf");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_red.vmt");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_neutral.vtf");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_neutral.vmt");

	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_red_dark.vmt");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_blue_dark.vmt");
	AddFileToDownloadsTable("materials/models/blap19/cappoint_logo_neutral_dark.vmt");
	
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap.sw.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap.vvd");

	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_2.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_2.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_2.sw.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_2.vvd");

	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_3.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_3.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_3.sw.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_3.vvd");

	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_4.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_4.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_4.sw.vtx");
	AddFileToDownloadsTable("models/blap19/ducks/bonus_blap_4.vvd");

	AddFileToDownloadsTable("models/blap19/cappoint_hologram.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/cappoint_hologram.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/cappoint_hologram.sw.vtx");
	AddFileToDownloadsTable("models/blap19/cappoint_hologram.vvd");

	AddFileToDownloadsTable("models/blap19/coins/coins.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coins.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coins.sw.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coins.vvd");
	AddFileToDownloadsTable("models/blap19/coins/coins.phy");

	AddFileToDownloadsTable("models/blap19/coins/coin_gravel.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_gravel.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_gravel.sw.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_gravel.vvd");
	AddFileToDownloadsTable("models/blap19/coins/coin_gravel.phy");
	AddFileToDownloadsTable("models/blap19/coins/coin_gravel.mdl");

	AddFileToDownloadsTable("models/blap19/coins/coin_bronze.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_bronze.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_bronze.sw.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_bronze.vvd");
	AddFileToDownloadsTable("models/blap19/coins/coin_bronze.phy");
	AddFileToDownloadsTable("models/blap19/coins/coin_bronze.mdl");

	AddFileToDownloadsTable("models/blap19/coins/coin_silver.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_silver.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_silver.sw.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_silver.vvd");
	AddFileToDownloadsTable("models/blap19/coins/coin_silver.phy");
	AddFileToDownloadsTable("models/blap19/coins/coin_silver.mdl");

	AddFileToDownloadsTable("models/blap19/coins/coin_gold.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_gold.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_gold.sw.vtx");
	AddFileToDownloadsTable("models/blap19/coins/coin_gold.vvd");
	AddFileToDownloadsTable("models/blap19/coins/coin_gold.phy");
	AddFileToDownloadsTable("models/blap19/coins/coin_gold.mdl");

	AddFileToDownloadsTable("models/blap19/notes/notes.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/notes/notes.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/notes/notes.sw.vtx");
	AddFileToDownloadsTable("models/blap19/notes/notes.vvd");
	AddFileToDownloadsTable("models/blap19/notes/notes.phy");

	AddFileToDownloadsTable("models/blap19/notes/note_1.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_1.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_1.sw.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_1.vvd");
	AddFileToDownloadsTable("models/blap19/notes/note_1.phy");
	AddFileToDownloadsTable("models/blap19/notes/note_1.mdl");

	AddFileToDownloadsTable("models/blap19/notes/note_2.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_2.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_2.sw.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_2.vvd");
	AddFileToDownloadsTable("models/blap19/notes/note_2.phy");
	AddFileToDownloadsTable("models/blap19/notes/note_2.mdl");

	AddFileToDownloadsTable("models/blap19/notes/note_3.dx80.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_3.dx90.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_3.sw.vtx");
	AddFileToDownloadsTable("models/blap19/notes/note_3.vvd");
	AddFileToDownloadsTable("models/blap19/notes/note_3.phy");
	AddFileToDownloadsTable("models/blap19/notes/note_3.mdl");
	
	for(int i = 1; i <= 29; i++) {
		char sound[PLATFORM_MAX_PATH];
		Format(sound, sizeof(sound), "misc/happy_birthday_tf_%02i.wav", i);
		PrecacheSound(sound);
	}

	PrecacheSound("passtime/horn_air2.wav");
	PrecacheSound("passtime/crowd_cheer.wav");
	PrecacheSound("mvm/mvm_bought_upgrade.wav");
	PrecacheSound("mvm/mvm_money_pickup.wav");
}