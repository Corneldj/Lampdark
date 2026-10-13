extends GutTest
## No physics node class or physics-space query in server/ or shared/ (GDD §15.8, FND-01).

const SCANNED_DIRS: Array[String] = ["res://server", "res://shared"]
const SCANNED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]
const FORBIDDEN: Array[String] = [
	"RigidBody2D", "RigidBody3D", "CharacterBody2D", "CharacterBody3D",
	"StaticBody2D", "StaticBody3D", "AnimatableBody2D", "AnimatableBody3D",
	"PhysicsBody2D", "PhysicsBody3D", "Area2D", "Area3D",
	"CollisionShape2D", "CollisionPolygon2D", "RayCast2D", "ShapeCast2D",
	"PhysicsServer2D", "PhysicsServer3D", "PhysicsDirectSpaceState2D",
	"PhysicsRayQueryParameters2D", "PhysicsShapeQueryParameters2D",
	"PhysicsPointQueryParameters2D", "direct_space_state", "intersect_ray",
	"intersect_shape", "intersect_point",
]


static func find_violations(source: String) -> Array[String]:
	var found: Array[String] = []
	for name: String in FORBIDDEN:
		if source.contains(name):
			found.append(name)
	return found


func _collect_files(dir: String, out: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() in SCANNED_EXTENSIONS:
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect_files(dir.path_join(sub), out)


func test_scanner_detects_physics() -> void:
	assert_eq(find_violations("var body: CharacterBody2D"), ["CharacterBody2D"] as Array[String])
	assert_eq(find_violations("space.intersect_ray(q)"), ["intersect_ray"] as Array[String])
	assert_eq(find_violations("var tile: Vector2i"), [] as Array[String])


func test_no_physics_in_server_or_shared() -> void:
	var files: Array[String] = []
	for dir: String in SCANNED_DIRS:
		_collect_files(dir, files)
	for path: String in files:
		var violations: Array[String] = find_violations(FileAccess.get_file_as_string(path))
		assert_eq(violations, [] as Array[String], "%s uses no physics" % path)
	pass_test("scanned %d files" % files.size())
