extends RefCounted

static func is_isolated() -> bool:
	var isolated := OS.get_environment("HEATSINK_TEST_DATA").replace("\\", "/")
	return not isolated.is_empty() and OS.get_user_data_dir().replace("\\", "/").begins_with(isolated + "/")
