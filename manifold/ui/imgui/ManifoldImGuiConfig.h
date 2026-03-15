#pragma once

struct ImGuiContext;
extern thread_local ImGuiContext* ManifoldGImGui;
#define GImGui ManifoldGImGui
