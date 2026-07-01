	HIGHWAY_OBJ_FILES_TMP := $(HIGHWAY_SRC_FILES:%.cc=%.o)
HIGHWAY_OBJ_FILES := $(HIGHWAY_OBJ_FILES_TMP:../../external/highway/hwy/%=../obj/highway/%)CC=gcc
CPP=g++
LINKFLAGS=-lstdc++ -lm 
CFLAGS=-I.
CPPFLAGS= -I.  -march=armv9-a -std=c++17 -frtti

RELEASE_CPP_FLAGS=-O3 -fomit-frame-pointer -finline-functions
DEBUG_CPP_FLAGS=-g -O0 -DDEBUG -D_DEBUG

#############################################
PWD := ${pwd}

HIGHWAY_SRC_DIR := ../../external/highway/hwy
HIGHWAY_SRC_FILES := $(HIGHWAY_SRC_DIR)/abort.cc \
		  $(HIGHWAY_SRC_DIR)/aligned_allocator.cc  \
		  $(HIGHWAY_SRC_DIR)/targets.cc \
		  $(HIGHWAY_SRC_DIR)/per_target.cc \
		  $(HIGHWAY_SRC_DIR)/print.cc

HIGHWAY_CFLAGS=-I../../external/highway

############################################
JUCE_SRC_DIR :=  ../../external/JUCE/modules/juce_core
JUCE_SRC_FILES := $(JUCE_SRC_DIR)/juce_core.cpp \
		  $(JUCE_SRC_DIR)/juce_core_CompilationTime.cpp

JUCE_CFLAGS=-I../../external/JUCE/modules \
            -DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1 \
            -DJUCE_USE_CURL=0

############################################

TEST_SRC_FILES := main.cpp TestADSRNode.cpp TestBitcrusherNode.cpp TestFilterNode.cpp TestGainNode.cpp TestingBase.cpp TestMixerNode.cpp TestOscillatorNode.cpp

TEST_CFLAGS=-I../.. \
	    -I../../external/JUCE/modules \
	    -I ../../external/highway \
	    -DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1  

TEST_HIGHWAY_DEPS := ../../manifold/highway/HighwayUtils.h \
                     ../../manifold/highway/HighwayWrapper.h \
		     ../../manifold/highway/HighwayMaths.h \
		     ../../manifold/highway/HighwaySmoother.h

############################################
DSP_DIR := ../../dsp/core/nodes
DSP_SRC_FILES := $(DSP_DIR)/ADSREnvelopeNode.cpp \
		 $(DSP_DIR)/BitCrusherNode.cpp \
		 $(DSP_DIR)/FilterNode.cpp \
	 	 $(DSP_DIR)/GainNode.cpp \
		 $(DSP_DIR)/MixerNode.cpp \
		 $(DSP_DIR)/OscillatorNode.cpp

DSP_CFLAGS=-I../.. \
            -I../../dsp/core/nodes \
		$(TEST_CFLAGS) \
		$(HIGHWAY_CFLAGS)

############################################


TEST_OBJ_FILES_DEBUG := $(TEST_SRC_FILES:%.cpp=../obj/main/debug/%.o)
TEST_OBJ_FILES_RELEASE := $(TEST_SRC_FILES:%.cpp=../obj/main/release/%.o)

HIGHWAY_OBJ_FILES_TMP := $(HIGHWAY_SRC_FILES:%.cc=%.o)
HIGHWAY_OBJ_FILES := $(HIGHWAY_OBJ_FILES_TMP:../../external/highway/hwy/%=../obj/highway/%)

DSP_OBJ_FILES_TMP := $(DSP_SRC_FILES:%.cpp=%.o)
DSP_OBJ_FILES_DEBUG := $(DSP_OBJ_FILES_TMP:../../dsp/core/nodes/%=../obj/dsp/debug/%)
DSP_OBJ_FILES_RELEASE := $(DSP_OBJ_FILES_TMP:../../dsp/core/nodes/%=../obj/dsp/release/%)

JUCE_OBJ_FILES_TMP := $(JUCE_SRC_FILES:%.cpp=%.o)
JUCE_OBJ_FILES_DEBUG := $(JUCE_OBJ_FILES_TMP:../../external/JUCE/modules/juce_core%=../obj/juce/debug/%)
JUCE_OBJ_FILES_RELEASE := $(JUCE_OBJ_FILES_TMP:../../external/JUCE/modules/juce_core%=../obj/juce/release/%)

#$(info $$TEST_OBJ_FILES $(TEST_OBJ_FILES))
#$(info $$TEST_SRC_FILES $(TEST_SRC_FILES))
#$(info $$HIGHWAY_OBJ_FILES $(HIGHWAY_OBJ_FILES))
#$(info $$HIGHWAY_OBJ_FILES_TMP $(HIGHWAY_OBJ_FILES_TMP))
#$(info $$HIGHWAY_SRC_FILES $(HIGHWAY_SRC_FILES))
#$(info $$DSP_OBJ_FILES $(DSP_OBJ_FILES))
#$(info $$DSP_OBJ_FILES_TMP $(DSP_OBJ_FILES_TMP))
#$(info $$DSP_SRC_FILES $(DSP_SRC_FILES))
#$(info $$JUCE_OBJ_FILES $(JUCE_OBJ_FILES))
#$(info $$JUCE_OBJ_FILES_TMP $(JUCE_OBJ_FILES_TMP))
#$(info $$JUCE_SRC_FILES $(JUCE_SRC_FILES))

############################################
all: testnodesapp testnodesapp_debug

release: testnodesapp

debug: testnodesapp_debug

$(HIGHWAY_OBJ_FILES): ../obj/highway/%.o: ../../external/highway/hwy/%.cc
	mkdir -p ../obj/highway && $(CPP) -c $< -o $@ $(CPPFLAGS) $(RELEASE_CPP_FLAGS)  $(HIGHWAY_CFLAGS)

$(JUCE_OBJ_FILES_DEBUG): ../obj/juce/debug/%.o: ../../external/JUCE/modules/juce_core/%.cpp
	mkdir -p ../obj/juce/debug && $(CPP) -c $< -o $@ $(CPPFLAGS) $(DEBUG_CPP_FLAGS)  $(JUCE_CFLAGS)

$(JUCE_OBJ_FILES_RELEASE): ../obj/juce/release/%.o: ../../external/JUCE/modules/juce_core/%.cpp
	mkdir -p ../obj/juce/release && $(CPP) -c $< -o $@ $(CPPFLAGS) $(RELEASE_CPP_FLAGS)  $(JUCE_CFLAGS)

$(TEST_OBJ_FILES_DEBUG):../obj/main/debug/%.o:%.cpp  $(TEST_HIGHWAY_DEPS)
	mkdir -p ../obj/main/debug && $(CPP) -c $< -o $@  $(CPPFLAGS) $(DEBUG_CPP_FLAGS) $(TEST_CFLAGS)

$(TEST_OBJ_FILES_RELEASE):../obj/main/release/%.o:%.cpp  $(TEST_HIGHWAY_DEPS)
	mkdir -p ../obj/main/release && $(CPP) -c $< -o $@  $(CPPFLAGS) $(RELEASE_CPP_FLAGS) $(TEST_CFLAGS)

$(DSP_OBJ_FILES_DEBUG):../obj/dsp/debug/%.o: ../../dsp/core/nodes/%.cpp $(TEST_HIGHWAY_DEPS)
	mkdir -p ../obj/dsp/debug && $(CPP) -c $< -o $@  $(CPPFLAGS) $(DEBUG_CPP_FLAGS)  $(DSP_CFLAGS)

$(DSP_OBJ_FILES_RELEASE):../obj/dsp/release/%.o: ../../dsp/core/nodes/%.cpp $(TEST_HIGHWAY_DEPS)
	mkdir -p ../obj/dsp/release && $(CPP) -c $< -o $@  $(CPPFLAGS) $(RELEASE_CPP_FLAGS) $(DSP_CFLAGS)

testnodesapp_debug: $(HIGHWAY_OBJ_FILES) $(TEST_OBJ_FILES_DEBUG) $(DSP_OBJ_FILES_DEBUG) $(JUCE_OBJ_FILES_DEBUG)
	$(CC) -o $@ $^ $(CFLAGS) $(DEBUG_CPP_FLAGS) $(LINKFLAGS)

testnodesapp: $(HIGHWAY_OBJ_FILES) $(TEST_OBJ_FILES_RELEASE) $(DSP_OBJ_FILES_RELEASE) $(JUCE_OBJ_FILES_RELEASE)
	$(CC) -o $@ $^ $(CFLAGS) $(RELEASE_CPP_FLAGS)  $(LINKFLAGS)

clean:
	rm -rv ../obj/main/debug/*.o || true
	rm -rv ../obj/main/release/*.o || true
	rm -rv ../obj/highway/*.o || true
	rm -rv ../obj/dsp/release/*.o || true
	rm -rv ../obj/dsp/debug/*.o || true
	rm -rv ../obj/juce/debug/*.o || true
	rm -rv ../obj/juce/release/*.o || true
	rm testnodesapp || true
