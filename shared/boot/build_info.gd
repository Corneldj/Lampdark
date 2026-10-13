class_name BuildInfo
extends RefCounted
## What kind of build is running: its flavour (dev, QA, release) and the role its tags imply.
##
## Feature tags (set by the export presets in export_presets.cfg):
##   lb_server / lb_client   the role a preset exports
##   lb_qa / lb_release      the flavour (debug or release template)
##   lb_killtest             QA-01's kill-test client
## Editor runs count as dev. An export carrying neither flavour tag is treated as release,
## so a misconfigured preset fails closed.

enum Flavour { DEV, QA, RELEASE }
enum Role { CLIENT, SERVER }

const TAG_SERVER: String = "lb_server"
const TAG_CLIENT: String = "lb_client"
const TAG_QA: String = "lb_qa"
const TAG_RELEASE: String = "lb_release"
const TAG_KILLTEST: String = "lb_killtest"

var flavour: Flavour = Flavour.RELEASE
## True when the build's tags fix the server role (a dedicated-server export).
var server_build: bool = false
## True when the build's tags fix the client role.
var client_build: bool = false
var kill_test: bool = false


static func detect(features: FeatureProvider) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	if features.has("editor"):
		info.flavour = Flavour.DEV
	elif features.has(TAG_RELEASE):
		info.flavour = Flavour.RELEASE
	elif features.has(TAG_QA):
		info.flavour = Flavour.QA
	else:
		info.flavour = Flavour.RELEASE
	info.server_build = features.has(TAG_SERVER)
	info.client_build = features.has(TAG_CLIENT)
	info.kill_test = features.has(TAG_KILLTEST)
	return info


func is_release() -> bool:
	return flavour == Flavour.RELEASE


## The role to run. A server export is always the server. In dev runs `--server` selects
## the server; elsewhere the client runs.
func role_for(wants_server: bool) -> Role:
	if server_build:
		return Role.SERVER
	if flavour == Flavour.DEV and not client_build and wants_server:
		return Role.SERVER
	return Role.CLIENT


func flavour_name() -> String:
	match flavour:
		Flavour.DEV:
			return "dev"
		Flavour.QA:
			return "qa"
	return "release"


## Tuning hot reload runs in dev always, in QA when asked (--tuning-hot-reload), and never in
## release (FND-05).
func allows_tuning_hot_reload(requested: bool) -> bool:
	if flavour == Flavour.RELEASE:
		return false
	return flavour == Flavour.DEV or requested
