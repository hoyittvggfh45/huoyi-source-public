package seku

func YoutubeCatalog(slot, category string, page int) ([]interface{}, int, bool, error) {
	return ytCatalog(slot, category, page)
}

func YoutubeSearch(slot, kw string) ([]interface{}, error) {
	return ytSearch(slot, kw)
}

func YoutubeDetail(slot, rawID string) (map[string]interface{}, error) {
	return ytDetail(slot, rawID)
}

func YoutubeResolve(slot, rawID string) (map[string]interface{}, error) {
	return ytResolve(slot, rawID)
}

func YoutubeCategories(slot string) []interface{} {
	return ytCategories(slot)
}

func YoutubeCategoryIDs() []string {
	ids := make([]string, 0, len(ytCats))
	for _, c := range ytCats {
		ids = append(ids, c.id)
	}
	return ids
}
