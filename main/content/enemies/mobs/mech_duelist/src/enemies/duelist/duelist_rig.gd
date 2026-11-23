extends Skeleton3D
## The pose targets stay in model space. Armor is attached to named, hierarchical bones.

const TOE_HINGE := Vector3(0, -0.103, -0.205)

var _targets: Array[Node3D] = []
var _parents: PackedInt32Array = []
var _poses: Array[Transform3D] = []


func attach(part: Node3D, bone_label: String, parent_bone: int) -> int:
	var index := add_bone(bone_label)
	set_bone_parent(index, parent_bone)
	_targets.append(part)
	_parents.append(parent_bone)
	_poses.append(Transform3D.IDENTITY)
	var attachment := BoneAttachment3D.new()
	attachment.name = bone_label + "_Geometry"
	add_child(attachment)
	attachment.bone_name = bone_label
	for child in part.get_children():
		if child is MeshInstance3D or child.has_meta(&"joint_detail"):
			child.reparent(attachment, false)
	return index


func pose_target(index: int) -> Node3D:
	return _targets[index]


func sync(rest := false) -> void:
	var inverse := global_transform.affine_inverse()
	for index in _targets.size():
		var pose := inverse * _targets[index].global_transform
		_poses[index] = pose
		var parent := _parents[index]
		var local := _poses[parent].affine_inverse() * pose if parent >= 0 else pose
		if rest:
			set_bone_rest(index, local)
		set_bone_pose(index, local)
