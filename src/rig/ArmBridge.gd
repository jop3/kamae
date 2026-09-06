class_name ArmBridge
extends SkeletonModifier3D
## Runs between the two arms' solvers. When one hand holds a weapon that the other hand also
## grips, the grip director uses this slot to read the solved holding hand live, move the weapon,
## and place the other hand's target before that arm solves, so both hands are exact in the same
## frame. The holding arm's modifiers are ordered before this node (CharacterRig.put_arm_first).

var callback: Callable


func _process_modification_with_delta(_delta: float) -> void:
	if callback.is_valid():
		callback.call()
