extends RefCounted
## Shot — tiny helpers for deterministic screenshots / frame stepping.
##
##   var shot = Shot.new()
##   await shot.capture(self, "res://shots/x.png", 30)   # wait N frames, save png

const DEFAULT_DIR := "res://shots"


func wait_frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


func capture(node: Node, path: String, settle_frames := 24) -> void:
	var tree := node.get_tree()
	await wait_frames(tree, settle_frames)
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEFAULT_DIR))
	var err := img.save_png(path)
	print("[shot] %s err=%d size=%s" % [path, err, str(img.get_size())])


## 固定步长推进：给确定性截图用，避免依赖真实帧率
func step_fixed(node: Node, seconds: float, step := 1.0 / 60.0) -> void:
	var t := 0.0
	var tree := node.get_tree()
	while t < seconds:
		t += step
		await tree.process_frame
