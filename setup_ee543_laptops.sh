#!/usr/bin/env bash
#===============================================================================
# setup_kinova_gen3lite_noetic.sh
#
# Set up for EE543 to use Kinova Gen3 Lite robots with the assigned workstations
#   - ROS Noetic (Ubuntu 20.04)
#   - Intel RealSense D435i
#   - MoveIt 1
#   - Gazebo 11 simulation
#   - Vision / perception pipeline
#
# Run as root or with sudo:
#   chmod +x setup_kinova_gen3lite_noetic.sh
#   sudo ./setup_kinova_gen3lite_noetic.sh
#
# After the script finishes:
#   1. Add student usernames with:  add_student_user <username>
#      (function defined at the bottom, or run the commands manually)
#   2. Reboot to pick up udev rules and group changes.S Kinova Gen3 Lite robotics worksta
#===============================================================================

set -eo pipefail

# ──────────────────────────────────────────────────────────────────────────────
#  CONFIG — edit these if needed
# ──────────────────────────────────────────────────────────────────────────────
ROS_DISTRO="noetic"
KORTEX_WS="/opt/ros_kortex_ws"          # shared catkin workspace for ros_kortex
KORTEX_BRANCH="noetic-devel"            # ros_kortex branch
CONAN_VERSION="1.59"                    # must be 1.x — 2.x breaks the build
STUDENT_USERS=("ee543student")                        # add student usernames here, e.g. ("alice" "bob")

# ──────────────────────────────────────────────────────────────────────────────
#  PREFLIGHT CHECKS
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: Please run this script as root (sudo)."
  exit 1
fi

if ! grep -q "20.04" /etc/os-release 2>/dev/null; then
  echo "WARNING: This script targets Ubuntu 20.04 (Focal). Detected:"
  grep PRETTY_NAME /etc/os-release || true
  read -rp "Continue anyway? [y/N] " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

echo "=========================================="
echo " Kinova Gen3 Lite — Full Noetic Setup"
echo "=========================================="

# ──────────────────────────────────────────────────────────────────────────────
#  1. ROS NOETIC INSTALLATION
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[1/9] Sourcing ROS Noetic..."

# if ! dpkg -l ros-noetic-desktop-full &>/dev/null; then
#   sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" \
#     > /etc/apt/sources.list.d/ros-latest.list'
#   apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' \
#     --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654 || true
#   apt-get update
#   apt-get install -y ros-noetic-desktop-full
# else
#   echo "  ros-noetic-desktop-full already installed, skipping."
# fi

# Source ROS for the rest of this script
source /opt/ros/noetic/setup.bash

# ──────────────────────────────────────────────────────────────────────────────
#  2. BUILD TOOLS & PYTHON DEPENDENCIES
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[2/9] Installing build tools and Python dependencies..."

apt-get install -y \
  build-essential \
  cmake \
  git \
  curl \
  wget \
  python3-pip \
  python3-catkin-tools \
  python3-rosdep \
  python3-rosinstall \
  python3-rosinstall-generator \
  python3-wstool \
  python3-numpy \
  python3-opencv \
  python3-yaml

# Initialize rosdep if not already done
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  rosdep init
fi
rosdep update --rosdistro=noetic || true

# Conan (required by ros_kortex build — MUST be 1.x)
pip3 install "conan==${CONAN_VERSION}"
conan config set general.revisions_enabled=1 || true
conan profile new default --detect --force
conan profile update settings.compiler.libcxx=libstdc++11 default

# ──────────────────────────────────────────────────────────────────────────────
#  3. KINOVA KORTEX SYSTEM DEPENDENCIES
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[3/9] Installing Kinova Kortex ROS dependencies..."

apt-get install -y \
  ros-noetic-ros-control \
  ros-noetic-ros-controllers \
  ros-noetic-gazebo-ros-control \
  ros-noetic-joint-state-controller \
  ros-noetic-effort-controllers \
  ros-noetic-position-controllers \
  ros-noetic-velocity-controllers \
  ros-noetic-joint-trajectory-controller \
  ros-noetic-gripper-action-controller \
  ros-noetic-xacro \
  ros-noetic-robot-state-publisher \
  ros-noetic-joint-state-publisher \
  ros-noetic-joint-state-publisher-gui \
  ros-noetic-diagnostic-updater \
  ros-noetic-control-msgs \
  ros-noetic-control-toolbox \
  ros-noetic-controller-manager \
  ros-noetic-actionlib \
  ros-noetic-actionlib-tools

# ──────────────────────────────────────────────────────────────────────────────
#  4. MOVEIT 1
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[4/9] Installing MoveIt..."

apt-get install -y \
  ros-noetic-moveit \
  ros-noetic-moveit-visual-tools \
  ros-noetic-moveit-ros-perception \
  ros-noetic-moveit-planners \
  ros-noetic-moveit-simple-controller-manager \
  ros-noetic-moveit-commander \
  ros-noetic-moveit-setup-assistant \
  ros-noetic-moveit-ros-visualization \
  ros-noetic-rviz-visual-tools \
  ros-noetic-trac-ik-kinematics-plugin

# ──────────────────────────────────────────────────────────────────────────────
#  5. INTEL REALSENSE D435i
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[5/9] Installing Intel RealSense SDK and ROS wrapper..."

# --- librealsense2 SDK from Intel's apt repo ---
if ! dpkg -l librealsense2-dkms &>/dev/null; then
  apt-key adv --keyserver keyserver.ubuntu.com \
    --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE || true
  add-apt-repository -y \
    "deb https://librealsense.intel.com/Debian/apt-repo focal main"
  apt-get update
fi

apt-get install -y \
  librealsense2-dkms \
  librealsense2-utils \
  librealsense2-dev \
  librealsense2-dbg

# --- ROS wrapper ---
apt-get install -y \
  ros-noetic-realsense2-camera \
  ros-noetic-realsense2-description \
  ros-noetic-rgbd-launch \
  ros-noetic-ddynamic-reconfigure

# ──────────────────────────────────────────────────────────────────────────────
#  6. VISION & PERCEPTION PIPELINE
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[6/9] Installing vision and perception packages..."

apt-get install -y \
  ros-noetic-cv-bridge \
  ros-noetic-image-transport \
  ros-noetic-image-transport-plugins \
  ros-noetic-image-pipeline \
  ros-noetic-depth-image-proc \
  ros-noetic-pcl-ros \
  ros-noetic-pcl-conversions \
  ros-noetic-tf2-ros \
  ros-noetic-tf2-tools \
  ros-noetic-tf2-sensor-msgs \
  ros-noetic-vision-opencv \
  ros-noetic-image-geometry \
  ros-noetic-camera-info-manager \
  ros-noetic-image-view

# ──────────────────────────────────────────────────────────────────────────────
#  7. CALIBRATION & UTILITY PACKAGES
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[7/9] Installing calibration, debug, and utility packages..."

apt-get install -y \
  ros-noetic-visp-hand2eye-calibration \
  ros-noetic-aruco-ros \
  ros-noetic-apriltag-ros \
  ros-noetic-camera-calibration \
  ros-noetic-topic-tools \
  ros-noetic-rqt \
  ros-noetic-rqt-common-plugins \
  ros-noetic-rqt-joint-trajectory-controller \
  ros-noetic-rqt-controller-manager \
  ros-noetic-rqt-tf-tree \
  ros-noetic-rqt-graph \
  ros-noetic-rqt-plot \
  ros-noetic-rqt-image-view \
  ros-noetic-rqt-reconfigure \
  ros-noetic-rqt-console

# ──────────────────────────────────────────────────────────────────────────────
#  8. GAZEBO SIMULATION EXTRAS
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[8/9] Installing Gazebo simulation packages..."

apt-get install -y \
  ros-noetic-gazebo-ros-pkgs \
  ros-noetic-gazebo-ros \
  ros-noetic-gazebo-plugins \
  ros-noetic-gazebo-msgs

# ──────────────────────────────────────────────────────────────────────────────
#  9. BUILD ros_kortex IN SHARED WORKSPACE
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "[9/9] Building ros_kortex in shared workspace: ${KORTEX_WS}..."

mkdir -p "${KORTEX_WS}/src"
cd "${KORTEX_WS}/src"

if [ ! -d "ros_kortex" ]; then
  git clone -b "${KORTEX_BRANCH}" \
    https://github.com/Kinovarobotics/ros_kortex.git
else
  echo "  ros_kortex already cloned, pulling latest..."
  cd ros_kortex && git pull && cd ..
fi

cd "${KORTEX_WS}"
source /opt/ros/noetic/setup.bash
rosdep install --from-paths src --ignore-src -y --rosdistro=noetic || true

catkin_make -DCATKIN_ENABLE_TESTING=False -DCMAKE_BUILD_TYPE=Release

# Make the workspace world-readable so non-admin students can source it
chmod -R a+rX "${KORTEX_WS}"

echo ""
echo "=========================================="
echo " ros_kortex built successfully at:"
echo "   ${KORTEX_WS}"
echo "=========================================="

# ──────────────────────────────────────────────────────────────────────────────
#  STUDENT ACCOUNT SETUP
# ──────────────────────────────────────────────────────────────────────────────

setup_student_bashrc() {
  local user="$1"
  local home_dir
  home_dir=$(eval echo "~${user}")

  # Add to dialout group (USB device access) and video group (camera access)
  usermod -aG dialout "${user}" 2>/dev/null || true
  usermod -aG video "${user}" 2>/dev/null || true
  usermod -aG plugdev "${user}" 2>/dev/null || true

  # Append ROS sourcing to .bashrc if not already present
  local bashrc="${home_dir}/.bashrc"
  if ! grep -q "ros/noetic/setup.bash" "${bashrc}" 2>/dev/null; then
    cat >> "${bashrc}" <<'ROSEOF'

# ── ROS Noetic ────────────────────────────────────────────────
source /opt/ros/noetic/setup.bash
ROSEOF
  fi

  if ! grep -q "ros_kortex_ws" "${bashrc}" 2>/dev/null; then
    cat >> "${bashrc}" <<KORTEXEOF

# ── Kinova Kortex workspace ──────────────────────────────────
if [ -f ${KORTEX_WS}/devel/setup.bash ]; then
  source ${KORTEX_WS}/devel/setup.bash
fi
KORTEXEOF
  fi

  # Make sure .bashrc is owned by the student
  chown "${user}:${user}" "${bashrc}"
  echo "  Configured .bashrc for user: ${user}"
}

# Process any student users listed in the config array
if [ ${#STUDENT_USERS[@]} -gt 0 ]; then
  echo ""
  echo "Setting up student accounts..."
  for student in "${STUDENT_USERS[@]}"; do
    if id "${student}" &>/dev/null; then
      setup_student_bashrc "${student}"
    else
      echo "  WARNING: User '${student}' does not exist. Skipping."
    fi
  done
fi

# ──────────────────────────────────────────────────────────────────────────────
#  HELPER FUNCTION — add students later
# ──────────────────────────────────────────────────────────────────────────────

cat <<'HELPER'

══════════════════════════════════════════════════════════════════
  SETUP COMPLETE — Next steps:
══════════════════════════════════════════════════════════════════

  1. REBOOT to apply udev rules and group changes:
       sudo reboot

  2. VERIFY RealSense camera (plug it in first):
       realsense-viewer

  3. ADD STUDENT USERS later by running:
       sudo usermod -aG dialout,video,plugdev <username>
     Then append to their ~/.bashrc:
       source /opt/ros/noetic/setup.bash
       source /opt/ros_kortex_ws/devel/setup.bash

  4. TEST the Kortex driver (with robot connected):
       roslaunch kortex_driver kortex_driver.launch \
         arm:=gen3_lite \
         gripper:=gen3_lite_2f \
         ip_address:=192.168.1.10

  5. TEST MoveIt (simulation, no robot needed):
       roslaunch kortex_move_it_config moveit_planning_execution.launch \
         arm:=gen3_lite \
         gripper:=gen3_lite_2f \
         use_sim_time:=true

  6. TEST RealSense camera:
       roslaunch realsense2_camera rs_camera.launch \
         align_depth:=true \
         enable_gyro:=true \
         enable_accel:=true

  TIP: For better IK performance, edit the MoveIt kinematics.yaml
       and switch from kdl_kinematics_plugin to:
         kinematics_solver: trac_ik_kinematics_plugin/TRAC_IKKinematicsPlugin

══════════════════════════════════════════════════════════════════
HELPER
