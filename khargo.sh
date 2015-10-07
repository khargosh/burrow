#!/bin/bash
#
# Description: Releases for this script are available at:
#   https://github.com/khargosh/burrow
#
# The above URL has a j.mp link as:
#   http://j.mp/khargosh
#
# The script is intended to be written and reviewed in the repository
# but released as a gist at the abovementioned URL.
#
# Executing this script requires issuing the following command:
#
#   curl -fsSL http://j.mp/khargosh > /tmp/khargo.sh
#   bash /tmp/khargo.sh
#
# To debug this script use:
#
#   bash -x /tmp/khargo.sh

# TODO(yesudeep):
# 1. Add error handling for installation of osxfuse.
# 2. Handle uninstall.
# 3. Silence the installation of .dotfiles.
# 4. Allow configuring the group name on the command line. Use default if not
#    specified.

MAKE_PAR_COUNT=8

now=`date`
src_dir=$HOME/src
logfile="/tmp/khargosh_config.log"


# WARNING: Do not include the packages listed hereinafter because they require
# special handling:
#
# ack-grep
# golang-go
# nodejs
# tup
linux_packages='
ant
autoconf
automake
binutils
bison
build-essential
bzr
cmake
emacs24
fastjar
fonts-roboto
git
git-svn
graphviz
graphviz-dev
intltool
java8-jdk
keychain
libfuse-dev
libncurses5-dev
libtool
m4
meld
mercurial
mosh
optipng
parallel
pdnsd
pkg-config
python-dev
python-pip
python-setuptools
reniced
ruby-dev
subversion
texinfo
tig
tree
unzip
vim
vim-gtk
vlc
wget
whois
xclip
'

# git is installed using brew because it has an up-to-date version
# that works with bash-completion.
brew_packages='
ack
ant
autoconf
automake
bash-completion
bison
bzr
clib
cmake
coreutils
emacs
fastjar
fish
gettext
git
graphviz
hg
intltool
keychain
libtool
macvim
mercurial
mosh
optipng
parallel
pdnsd
pkg-config
readline
ssh-copy-id
subversion
tig
tree
tup
vim
wget
'

python_packages='
bpython
http://closure-linter.googlecode.com/files/closure_linter-latest.tar.gz
ipython[all]
networkx
sphinx
twisted
'

# NOTE(sandeep): Why aren't we building protoc-gen-go via source?
# Building protoc-gen-go from source and placing it inside bhojo/bin won't work
# since protoc compiler will look for it in environment $PATH variable when
# generating golang source files.
additional_go_packages='
github.com/golang/lint/golint
github.com/golang/protobuf/proto
github.com/golang/protobuf/protoc-gen-go
github.com/kisielk/errcheck
github.com/mkouhei/gosh
github.com/nsf/gocode
github.com/onsi/ginkgo/ginkgo
github.com/onsi/gomega
github.com/rogpeppe/godef
github.com/smartystreets/goconvey
golang.org/x/mobile
golang.org/x/mobile/cmd/gobind
golang.org/x/mobile/cmd/gomobile
golang.org/x/review/git-codereview
golang.org/x/tools/cmd/benchcmp
golang.org/x/tools/cmd/callgraph
golang.org/x/tools/cmd/cover
golang.org/x/tools/cmd/digraph
golang.org/x/tools/cmd/eg
golang.org/x/tools/cmd/godex
golang.org/x/tools/cmd/godoc
golang.org/x/tools/cmd/goimports
golang.org/x/tools/cmd/gorename
golang.org/x/tools/cmd/gotype
golang.org/x/tools/cmd/html2article
golang.org/x/tools/cmd/oracle
golang.org/x/tools/cmd/present
golang.org/x/tools/cmd/ssadump
golang.org/x/tools/cmd/stringer
golang.org/x/tools/cmd/vet
golang.org/x/tour/gotour
'

npm_packages='
bower
karma
karma-cli
bhojo/karma-closure
karma-jasmine
karma-phantomjs-launcher
'

# Keep sorted. To enlist packages, run `android list sdk --extended`:
android_packages='
addon-google_apis-google-19
addon-google_apis-google-21
addon-google_apis_x86-google-19
android-19
android-20
android-21
build-tools-21.1.2
doc-21
extra-android-support
extra-google-google_play_services
extra-google-play_billing
extra-google-play_licensing
extra-google-simulators
extra-google-webdriver
platform-tools
'
android_packages=`echo $android_packages | tr ' ' ','`


# Push directory silent.
function pushdir() {
  pushd "$@" >/dev/null 2>&1
}


# Pop directory silent.
function popdir() {
  popd "$@" >/dev/null 2>&1
}


# Logs information to the console.
function info() {
  printf "$1\n" | tee -a $logfile
}


# Logs information to the console.
function error() {
  printf "error: $1\n" | tee -a $logfile
}


# Compares two version strings.
#
# @see http://stackoverflow.com/questions/4023830/bash-how-compare-two-strings-in-version-format
#
# @param {a} The first version string.
# @param {b} The second version string.
#
# @return 2 if a < b, 0 if a and b are equal, 1 if a > b.
function compare_versions() {
  if [[ $1 == $2 ]]
  then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
  do
    ver1[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++))
  do
    if [[ -z ${ver2[i]} ]]
    then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]}))
    then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]}))
    then
      return 2
    fi
  done
  return 0
}


# Tests the compare versions function.
function test_compare_versions() {
  compare_versions $1 $2
  case $? in
    0) op='=';;
    1) op='>';;
    2) op='<';;
  esac
  if [[ $op != $3 ]]
  then
    echo "FAIL: Expected '$3', Actual '$op', Arg1 '$1', Arg2 '$2'"
  else
    echo "Pass: '$1 $op $2'"
  fi
}


# Ensure that the user running this script is not root or has administrative
# privileges. Some of the files generated by this script require to be built
# and installed in the user's home directory to avoid polluting the host
# system.
function assert_non_root_user() {
  user=`id -u`
  if [ $user == 0 ]; then
    echo "Please run this script without using sudo."
    exit 1
  fi
}


# Prompt yes or no.
#
# @param {message} String message to display when showing the prompt.
# @param {default} String representing the default value.
function prompt_yes_no () {
  message=$1
  default=${2:-"Y"}
  while true; do
    read -p "$message " yn
    case ${yn:-$default} in
      [Yy]* )
        return 0 ;;
      [Nn]* )
        return 1 ;;
      * )
        echo "Please answer yes or no." ;;
    esac
  done
}


# Displays a banner preamble before proceeding with the installation.
function show_preamble() {
  info "Source code download directory: $HOME/src"
  info "Bash environment variables defined in: $HOME/.path_environment"
  info "Fish environment variables defined in: $HOME/.config/fish/config.fish"
}


# Displays an epilog.
function show_epilog() {
  info "Installation completed."
  info "Please restart your system for good measure and hack away!"
}


# Synchronizes a git repository for source code.
#
# @param {repo_path} A string representing the repository path.
function sync_git_repo(){
  repo_path=$1
  repo_dir=$src_dir/$repo_path
  echo "Synchronizing git repo: $repo_dir" | tee -a $logfile
  if [ ! -d $repo_dir ]; then
    git clone --recursive git://$repo_path $repo_dir >> $logfile 2>&1
  else
    cd $repo_dir
    git checkout master >> $logfile 2>&1
    git pull origin master >> $logfile 2>&1
  fi
}


# Rotates log files.
# See: http://wazem.blogspot.in/2013/11/simple-bash-log-rotate-function.html
#
# @param {preamble} Preamble text.
# @param {log} The log file.
function rotate_logfile() {
  preamble=$1
  log=$2

  # Deletes old log file
  if [ ! -f $log ]; then
    printf "$preamble\n" | tee $log
  else
    count=5
    let p_count=count-1
    if [ -f ${log}.5 ] ; then
      rm ${log}.5
    fi

    # Renames logs .1 trough .4
    while [[ $count -ne 1 ]] ; do
      if [ -f ${log}.${p_count} ] ; then
        mv ${log}.${p_count} ${log}.${count}
      fi
      let count=count-1
      let p_count=p_count-1
    done

    # Renames current log to .1
    mv $log ${log}.1
    printf "$preamble\n" | tee $log
  fi
}


# Extracts a tar.gz archive.
#
# @param {archive}
function extract_tar_gz() {
  archive=$1
  info "Extracting $archive"
  tar zxvf $archive >> $logfile 2>&1
}


# Extracts a tar.bz2 archive.
#
# @param {archive}
function extract_tar_bz2() {
  archive=$1
  info "Extracting $archive"
  tar jxvf $archive >> $logfile 2>&1
}


# Downloads a resource given its URL to a destination file.
#
# @param {url} A string representing the URL from where to fetch the resource.
# @param {destination} A String representing the path where the resource should
#   be saved.
function download() {
  url=$1
  destination=$2
  if command -v 'wget' &>/dev/null ; then
    info "Downloading using wget: $url"
    wget -c $url -O $destination -o $logfile 2>&1
    if [ $? != 0 ]; then
      error "cannot download $url"
      exit 1
    fi
  elif command -v 'curl' &>/dev/null ; then
    info "Downloading using curl: $url"
    curl -o $destination $url | tee -a $logfile 2>&1
    if [ $? != 0 ]; then
      error "cannot download $url"
      exit 1
    fi
  else
    error "cannot find curl or wget to download $url. aborting."
    exit 1
  fi
}


# Mounts a Mac OS X DMG as a volume.
#
# @param {dmg_file} The path to the DMG file to mount.
# @param {volume_name} The name of the volume label.
function macosx_attach_dmg() {
  dmg_file=$1
  volume_name=$2

  info "Mounting $1 at $2"
  hdiutil attach $dmg_file -noverify -nobrowse -mountpoint /Volumes/$volume_name 1>/dev/null 2>&1
  if [ $? != 0 ]; then
    echo "error: unable to mount DMG -- please unmount /Volumes/$volume_name first."
    exit 1
  fi
}


# Unmounts a mac os x volume.
#
# @param {volume_name} The volume to unmount.
function macosx_detach_volume() {
  volume_name=$1
  info "Unmounting /Volumes/$volume_name"
  hdiutil detach /Volumes/$volume_name 1>/dev/null 2>&1
}


# Installs OS X fuse from osxfuse.github.io instead of using Homebrew because
# Yosemite no longer allows unsigned kexts.
#
# @param {version} String of version triplet representing the version to fetch.
function install_osxfuse() {
  version=$1

  info "Installing osxfuse."
  download \
    http://internode.dl.sourceforge.net/project/osxfuse/osxfuse-${version}/osxfuse-${version}.dmg \
    /tmp/osxfuse-${version}.dmg
  macosx_attach_dmg /tmp/osxfuse-${version}.dmg osxfuse-$version
  pkg_file=`find /Volumes/osxfuse-$version -type f -name "*.pkg" 2>/dev/null`
  if [ "X$pkg_file" = "X" ] ; then
    echo "error: cannot find PKG file inside DMG -- nothing to install!"
    exit 1
  fi
  # pkgutil --expand "$pkg_file" /tmp/dir_$$
  info "Installing osxfuse-$version"
  sudo /usr/sbin/installer -pkg "$pkg_file" -target / >> $logfile 2>&1
  macosx_detach_volume osxfuse-$version
}


# Installs xcode command line tools.
function install_xcode_tools() {
  info "Installing XCode Command Line tools"
  xcode-select --install 2>/dev/null
}


# Installs homebrew.
function install_homebrew() {
  if ! command -v 'brew' &>/dev/null ; then
    info "Installing homebrew for Mac OS X"
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  fi
  info "Diagnosing homebrew. Please see $logfile for more details."
  brew doctor >> $logfile 2>&1
  info "Updating brew package indexes."
  brew update >> $logfile 2>&1
  info "Upgrading stale packages."
  brew upgrade >> $logfile 2>&1
}


# Installs python packages with pip.
#
# @param {spec...} Package specifications separated by spaces.
function install_python_packages() {
  spec="$@"
  case "$OSTYPE" in
    "linux-gnu" )
      if [ ! command -v 'pip' &>/dev/null ]; then
        info "Installing Python pip."
        sudo aptitude -y install python-pip >> $logfile 2>&1
      fi
      ;;
    "darwin"* )
      if [ ! command -v 'pip' &>/dev/null ]; then
        info "Installing Python pip."
        sudo easy_install pip >> $logfile 2>&1
      fi
      ;;
  esac
  # pkgs=`$spec | tr ' ' '\n'`
  info "Installing Python packages: $spec"
  sudo pip install --upgrade $spec >> $logfile 2>&1
}


# Installs the Android SDK.
#
# @param {version} The version of the SDK to fetch.
# @param {packages} A command line comma-separated list of packages.
function install_android_sdk() {
  version=$1
  packages=$2

  # We use this standard directory for the android installation.
  if [ ! -d "$HOME/Library/Android/sdk" ]; then
    mkdir -p $HOME/Library/Android
    case "$OSTYPE" in
      "linux-gnu" )
        url="http://dl.google.com/android/android-sdk_${version}-linux.tgz"
        download $url /tmp/android-sdk_${version}-linux.tgz
        rm -rf /tmp/android-sdk-linux
        pushdir tmp
        extract_tar_gz /tmp/android-sdk_${version}-linux.tgz
        mv android-sdk-linux $HOME/Library/Android/sdk
        popdir

        # 32-bit libraries are required for the SDK.
        case "$machine_arch" in
          i?86)
            sudo apt-get install \
              libncurses5 \
              libstdc++6 \
              zlib1g \
              | tee -a $logfile
            ;;
          x86_64)
            sudo dpkg --add-architecture i386 | tee -a $logfile
            sudo aptitude update | tee -a $logfile
            sudo aptitude install \
              lib32stdc++6 \
              lib32z1 \
              lib32z1-dev \
              libncurses5:i386 \
              libstdc++6:i386 \
              zlib1g:i386 \
              | tee -a $logfile
            ;;
        esac

        ;;
      "darwin"* )
        url="http://dl.google.com/android/android-sdk_${version}-macosx.zip"
        download $url /tmp/android-sdk_${version}-macosx.zip
        rm -rf /tmp/android-sdk-macosx
        pushdir /tmp
        unzip android-sdk_${version}-macosx.zip >> $logfile 2>&1
        mv /tmp/android-sdk-macosx $HOME/Library/Android/sdk
        popdir
        ;;
    esac
  fi

  # Now install additional tools.
  echo y | $HOME/Library/Android/sdk/tools/android update sdk --no-ui --force -t $packages
}


# Installs the Dart SDK.
#
# @param {channel} The channel of the SDK to install for (dev|stable)
# @param {revision} The revision of the SDK to install (see
#   https://www.dartlang.org/tools/download-archive/).
# @param {min_version} The required version to check.
function install_dart_sdk() {
  channel=${1:-stable}
  revision=${2:-44672}
  min_version=${3:-"1.9.1"}

  machine_arch=`uname -m`
  arch="x64"
  have_version=`dart --version 2>&1 | awk '{ print $4 }'`
  have_version=`echo $have_version | awk -F. '{ print $1.$2.$3 }'`
  required_version=`echo $min_version | awk -F. '{ print $1.$2.$3 }'`

  # TODO(yesudeep): Add version detection.
  if ! command -v "$HOME/dart-sdk/bin/dart" &>/dev/null || [[ "$required_version" -gt "$have_version" ]]; then
    case "$machine_arch" in
      i?86)
        # 32-bit installation of dart.
        arch='ia32'
        ;;
      x86_64)
        # 64-bit installation of dart.
        arch='x64'
        ;;
    esac
    os="linux"
    case "$OSTYPE" in
      "linux-gnu" )
        os="linux"
        ;;
      "darwin"* )
        os="macos"
        ;;
    esac
    outfile_name="dartsdk-${os}-${arch}-release.zip"
    url="https://storage.googleapis.com/dart-archive/channels/${channel}/release/${revision}/sdk/${outfile_name}"
    info "Downloading Dart SDK: ${outfile_name}"
    download $url "$HOME/${outfile_name}"
    rm -rf $HOME/dart-sdk 2>/dev/null
    pushdir $HOME
    info "Installing in $HOME/dart-sdk"
    unzip $outfile_name >> $logfile 2>&1
    popdir
  fi
}


# Displays usage.
function show_usage() {
  echo " "
  echo "USAGE: $0 [OPTIONS]"
  echo " "
  echo "OPTIONS:"
  echo "       -h                print usage and exit"
  echo "       -U                uninstall everything that was installed"
  echo " "
  echo "EXAMPLES:"
  echo " "
  echo "       $0 -h :           prints out help information"
  echo "  sudo $0    :           displays an error to not run as administrator"
  echo "       $0 -U :           uninstalls everything installed previously"
  echo " "
}


# Installs and configures ack.
function install_ack() {
  case "$OSTYPE" in
    "linux-gnu" )
      sudo aptitude -y install ack-grep | tee -a $logfile
      sudo ln -s `which ack-grep` /usr/local/bin/ack >> $logfile 2>&1
      ;;
    "darwin"* )
      brew install ack >> $logfile 2>&1
      ;;
  esac
}


# Installs tmux on Ubuntu machines that have an older version of tmux.
#
# NOTE(yesudeep): This is currently only required because tmux 1.9a is required
# at the bare minimum. Once this requirement goes away, we can install tmux
# usually without a special method to handle its installation.
#
# @param {tmux_version} The version number to install.
# @param {tmux_patch_version} The patch version to install. Leave as empty
#   string for stable releases
# @param {libevent_version} The version for libevent to install.
# @param {ncurses_version} The version for ncurses to install.
function install_tmux() {
  tmux_version=$1
  tmux_patch_version=$2
  libevent_version=$3
  ncurses_version=$4

  case "$OSTYPE" in
    "linux-gnu" )
      # sudo aptitude -y remove tmux >> $logfile 2>&1
      sudo aptitude -y install tmux | tee -a $logfile
      have_version=`tmux -V | cut -d ' ' -f 2`
      compare_versions $tmux_version $have_version
      op=$?
      if ! command -v "tmux" &>/dev/null || [[ $op == 1 ]]; then
        tmux_name="tmux-$tmux_version"
        tmux_relative_url="$tmux_name/$tmux_name$tmux_patch_version"
        libevent_name="libevent-$libevent_version-stable"
        ncurses_name="ncurses-$ncurses_version"

        # set the installation directory
        target_dir="/usr/local"

        # download source files for tmux, libevent, and ncurses
        download \
          http://sourceforge.net/projects/tmux/files/tmux/$tmux_relative_url.tar.gz/download \
          /tmp/${tmux_name}.tar.gz
        download \
          https://github.com/downloads/libevent/libevent/$libevent_name.tar.gz \
          /tmp/${libevent_name}.tar.gz
        download \
          ftp://ftp.gnu.org/gnu/ncurses/$ncurses_name.tar.gz \
          /tmp/${ncurses_name}.tar.gz

        # extract files, configure, compile, and install

        # libevent installation
        extract_tar_gz $libevent_name.tar.gz
        pushdir /tmp/$libevent_name
        info "Configuring $libevent_name"
        ./configure --prefix=$target_dir --disable-shared >> $logfile 2>&1
        info "Building $libevent_name"
        make -j $MAKE_PAR_COUNT >> $logfile 2>&1
        info "Installing $libevent_name"
        sudo make install >> $logfile 2>&1
        popdir

        # ncurses installation
        extract_tar_gz $ncurses_name.tar.gz
        pushdir /tmp/$ncurses_name
        info "Configuring $ncurses_name"
        ./configure --prefix=$target_dir >> $logfile 2>&1
        info "Building $ncurses_name"
        make -j $MAKE_PAR_COUNT >> $logfile 2>&1
        info "Installing $ncurses_name"
        sudo make install >> $logfile 2>&1
        popdir

        # tmux installation
        extract_tar_gz ${tmux_name}*.tar.gz
        pushdir /tmp/${tmux_name}*/
        info "Configuring $tmux_name"
        ./configure \
          CFLAGS="-I$target_dir/include -I$target_dir/include/ncurses" \
          LDFLAGS="-L$target_dir/lib -L$target_dir/include/ncurses -L$target_dir/include" \
          >> $logfile 2>&1
        info "Building $tmux_name"
        CPPFLAGS="-I$target_dir/include -I$target_dir/include/ncurses" \
          LDFLAGS="-static -L$target_dir/include -L$target_dir/include/ncurses -L$target_dir/lib" \
          make -j $MAKE_PAR_COUNT >> $logfile 2>&1
        info "Installing $tmux_name"
        sudo cp tmux $target_dir/bin >> $logfile 2>&1
        popdir
      fi
      ;;
    "darwin"* )
      # TODO(yesudeep): Currently versioning for this is not implemented.
      brew install tmux >> $logfile 2>&1
      ;;
  esac

}

function set_go_env_osx() {
  go_root_dir=$1
  go_path_dir=$2

  # Add the environment variables for OS X < Yosemite.
  grep -q "setenv GOROOT $go_root_dir" /etc/launchd.conf || \
    printf "setenv GOROOT $go_root_dir\nsetenv GOPATH $go_path_dir\nsetenv PATH \$GOPATH/bin:\$GOROOT/bin:\$PATH\n" | \
      sudo tee -a /etc/launchd.conf >> $logfile 2>&1

  # Using /etc/launchd.conf no longer works for Yosemite and above: http://goo.gl/0SCH3i
  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key>
  <string>org.golang.environment</string>
  <key>ProgramArguments</key>
  <array>
    <string>sh</string>
    <string>-c</string>
    <string>
    launchctl setenv GOROOT $go_root_dir
    launchctl setenv GOPATH $go_path_dir
    </string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>" | sudo tee "/Library/LaunchAgents/org.golang.environment.plist" >> $logfile 2>&1

  # The above cannot be used to set $PATH in Yosemite, but according to
  # http://goo.gl/tJZkGw we need to use /etc/paths.
  grep -q "${go_root_dir}/bin" /etc/paths || \
    printf "${go_root_dir}/bin\n${go_root_dir}/bin\n" | sudo tee -a /etc/paths >> $logfile 2>&1
}

function install_go() {
  go_version=$1
  additional_packages="${@:2}"

  install_dir="/usr/local"
  go_root_dir="$install_dir/go"
  go_path_dir="$install_dir/golib"
  have_version=`go version 2>&1 | awk -Fgo '{ print $3 }' | awk '{ print $1 }'`

  # Remove incompatible versions of go packages.
  case "$OSTYPE" in
    "linux-gnu" )
      sudo aptitude -y remove golang-go | tee -a $logfile
      ;;
    "darwin"* )
      brew remove go >> $logfile 2>&1
      ;;
  esac

  # Check go version and install.
  compare_versions $go_version $have_version
  op=$?
  if ! command -v "$go_root_dir/bin/go" &>/dev/null || [[ $op == 1 ]]; then
    if [ -d $go_root_dir ]; then
      info "Removing any existing installation of go."
      sudo rm -rf $go_root_dir
    fi
    if [ -d $go_path_dir ]; then
      info "Removing existing installed go path."
      sudo rm -rf $go_path_dir
    fi

    # Download and extract to the temporary directory.
    info "Installing Go $go_version"
    info "Setting \$GOROOT=$go_root_dir"
    info "Setting \$GOPATH=$go_path_dir"

    machine_arch=`uname -m`
    arch="amd64"
    case "$machine_arch" in
      i?86)
        arch='386'
        ;;
      x86_64)
        arch='amd64'
        ;;
    esac

    case "$OSTYPE" in
      "linux-gnu" )
        download "https://storage.googleapis.com/golang/go${go_version}.linux-${arch}.tar.gz" "/tmp/go${go_version}.linux-${arch}.tar.gz"
        pushd /tmp
        tar zxvf "/tmp/go${go_version}.linux-${arch}.tar.gz"
        sudo mv go/ /usr/local/
        popd
        info "Installing additional go packages:\n$additional_packages"
        sudo mkdir -p ${go_path_dir}
        sudo env GOPATH="${go_path_dir}" ${go_root_dir}/bin/go get -u $additional_packages >> $logfile 2>&1
        ;;
      "darwin"* )
        mkdir -p $go_path_dir
        pkg_file="/tmp/go${go_version}.darwin-${arch}.pkg"
        download "https://storage.googleapis.com/golang/go${go_version}.darwin-${arch}.pkg" $pkg_file
        sudo /usr/sbin/installer -pkg "$pkg_file" -target / >> $logfile 2>&1
        info "Installing additional go packages:\n$additional_packages"
        env GOPATH=${go_path_dir} ${go_root_dir}/bin/go get -u $additional_packages >> $logfile 2>&1
        set_go_env_osx ${go_root_dir} ${go_path_dir}
        ;;
    esac
  fi
}

# Installs go compilers and tools for golang development.
#
# @param {go_version} A string representing the version number of the go
#   toolset to install.
# @param {additional_packages...} Additional packages to install for go.
function install_go_old() {
  go_version=$1
  additional_packages="${@:2}"

  install_dir="/usr/local"
  go_root_dir="$install_dir/go"
  go_path_dir="$install_dir/golib"
  # have_version=`go version 2>&1 | awk -Fgo '{ print $3 }' | awk '{ print $1 }'`
  # have_version=`echo $have_version | awk -F. '{ print $1.$2.$3 }'`
  # required_version=`echo $go_version | awk -F. '{ print $1.$2.$3 }'`
  have_version=`go version 2>&1 | awk -Fgo '{ print $3 }' | awk '{ print $1 }'`
  required_version=$go_version


  # Remove incompatible versions of go packages.
  case "$OSTYPE" in
    "linux-gnu" )
      sudo aptitude -y remove golang-go | tee -a $logfile
      ;;
    "darwin"* )
      brew remove go >> $logfile 2>&1
      ;;
  esac

  # Check go version and install.
  compare_versions $go_version $have_version
  op=$?
  if ! command -v "$go_root_dir/bin/go" &>/dev/null || [[ $op == 1 ]]; then
    # Download and extract to the temporary directory.
    info "Installing Google Go $go_version"
    info "Setting \$GOROOT=$go_root_dir"
    info "Setting \$GOPATH=$go_path_dir"
    download "https://storage.googleapis.com/golang/go${go_version}.src.tar.gz" "/tmp/go${go_version}.src.tar.gz"
    pushdir /tmp
    tar zxvf go${go_version}.src.tar.gz >> $logfile 2>&1

    # Remove existing go (group-based) installation if any.
    if [ -d $go_root_dir ]; then
      sudo rm -rf $go_root_dir
    fi

    # Remove existing go (group-based) lib dir if any to upgrade packages
    # cleanly.
    if [ -d $go_path_dir ]; then
      sudo rm -rf $go_path_dir
    fi

    # Go compiles the $GOROOT path into the executable and therefore, we must
    # build go where it needs to be installed. We tried compiling it without the
    # permissions hassle in /tmp/go, but that caused go to compile $GOROOT as
    # /tmp/go. Therefore, after having moved the go directory to /usr/local/...
    # it kept complaining about missing $GOROOT. To avoid all this hassle, we
    # build go where it needs to finally live.
    case "$OSTYPE" in
      "linux-gnu" )
        sudo mkdir -p $go_path_dir
        sudo mv /tmp/go $install_dir/

        # We need to change permissions because the source code will be built
        # using the current user's account.
        sudo chown -R $USER $go_root_dir
        pushdir $go_root_dir/src
        info "Building go"
        ./make.bash >> $logfile 2>&1
        popdir

        info "Installing additional go packages:\n$additional_packages"
        sudo env GOPATH=${go_path_dir} ${go_root_dir}/bin/go get -u $additional_packages >> $logfile 2>&1

        # Now create the actual permissions for updates and further installation
        # by other and current user.
        sudo groupadd admins
        sudo usermod -a -G admins $USER
        sudo chown -R root\:admins $install_dir
        sudo chmod -R g+w $install_dir

        # Apparently, permissions get borked on some versions of Ubuntu. Add
        # appropriate permissions to get directories to be accessible.
        sudo find $go_root_dir -type d -print0 | xargs -0 sudo chmod 755
        # Overwrite.
        printf "export GOROOT=$go_root_dir\nexport GOPATH=$go_path_dir\nexport PATH=\$GOPATH/bin:\$GOROOT/bin:\$PATH\n" | sudo tee /etc/profile.d/goenv.sh >> $logfile 2>&1
        ;;

      "darwin"* )
        mkdir -p $go_path_dir
        mv /tmp/go $install_dir/
        pushdir $go_root_dir/src 2>/dev/null
        info "Building go"
        ./make.bash >> $logfile 2>&1
        popdir

        ;;
    esac

    popdir
  fi;
}


# Uninstalls go.
function uninstall_go() {
  go_root_dir="/usr/local/go"
  go_path_dir="/usr/local/golib"
  sudo rm -rf $go_root_dir $go_path_dir
}


# Installs packages using brew on Mac OS X.
#
# WARNING: Does not perform OS detection.
#
# @param {pkg_names} A space-separated list of packages.
function install_brew_packages() {
  pkg_names="$@"
  # pkgs=`$pkg_names | tr ' ' '\n'`
  info "Installing packages: $pkg_names"
  brew install $pkg_names >> $logfile 2>&1
}


# Uninstalls packages using brew on Mac OS X.
#
# WARNING: Does not perform OS detection.
#
# @param {pkg_names} A space-separated list of packages.
function uninstall_brew_packages() {
  pkg_names="$@"
  # pkgs=`$pkg_names | tr ' ' '\n'`
  info "Uninstalling packages: $pkg_names"
  brew uninstall $pkg_names >> $logfile 2>&1
}


# Installs packages using aptitude on Ubuntu.
#
# WARNING: Does not perform OS detection.
#
# @param {pkg_names} A space-separated list of packages.
function install_linux_packages() {
  pkg_names="$@"
  # pkgs=`$pkg_names | tr ' ' '\n'`
  info "Installing packages: $pkg_names"
  sudo aptitude install -y $pkg_names | tee -a $logfile
}


# Uninstalls packages using aptitude on Ubuntu.
#
# WARNING: Does not perform OS detection.
#
# @param {pkg_names} A space-separated list of packages.
function uninstall_linux_packages() {
  pkg_names="$@"
  # pkgs=`$pkg_names | tr ' ' '\n'`
  info "Uninstalling packages: $pkg_names"
  sudo aptitude remove -y $pkg_names >> $logfile 2>&1
}


# Don't install dotfiles twice.
#
# @param {rc_file} The RC file to check and add to.
function check_install_dotfiles() {
  rc_file=$1
  grep -q "source \"\$HOME/.dotfiles/bashrc\"" $rc_file || \
    printf "\n\nif [ -f \"\$HOME/.dotfiles/bashrc\" ]; then\n  source \"\$HOME/.dotfiles/bashrc\"\nfi\n\n"\
           >> $rc_file
}


# Configures emacs for use.
function install_emacs_config() {
  # Removes older styles of installing emacs.
  if [ ! -h $HOME/.emacs.d ]; then
    rm -rf $HOME/.emacs.d
  fi
  sync_git_repo github.com/gorakhargosh/gemacs
  ln -s $src_dir/github.com/gorakhargosh/gemacs $HOME/.emacs.d 2>/dev/null
}


# Installs watchman for a specific version.
#
# @param {version} Version.
function install_watchman() {
  version=$1
  sync_git_repo github.com/facebook/watchman
  pushdir $HOME/src/github.com/facebook/watchman

  info "Checking out version $version"
  git checkout $version >> $logfile 2>&1
  info "Configuring watchman"
  ./autogen.sh >> $logfile 2>&1
  ./configure --prefix=$HOME/var >> $logfile 2>&1
  info "Building watchman"
  make -j $MAKE_PAR_COUNT >> $logfile 2>&1
  info "Installing watchman."
  make install >> $logfile 2>&1
  git checkout master >> $logfile 2>&1
  popdir
}


# Installs buck for a specific version.
#
# @param {version} Version.
function install_buck() {
  version=$1
  sync_git_repo github.com/facebook/buck
  pushdir $HOME/src/github.com/facebook/buck

  info "Checking out version $version"
  git checkout $version >> $logfile 2>&1
  info "Building buck"
  ant && bin/buck build buck >> $logfile 2>&1
  info "Installing buck."

  rm -rf $HOME/var/bin/buck && \
    ln -s $HOME/src/github.com/facebook/buck/bin/buck $HOME/var/bin/buck >> $logfile 2>&1
  git checkout master >> $logfile 2>&1

  popdir
}



# Installs shell and emacs configuration
function install_shell_config() {
  if [ ! -h $HOME/.dotfiles ]; then
    rm -rf $HOME/.dotfiles
  fi
  sync_git_repo github.com/gorakhargosh/dotfiles
  ln -s $src_dir/github.com/gorakhargosh/dotfiles $HOME/.dotfiles 2>/dev/null

  # Dont install twice.
  case "$OSTYPE" in
    "linux-gnu" )
      check_install_dotfiles "$HOME/.bashrc"
      ;;
    "darwin"* )
      check_install_dotfiles "$HOME/.bash_profile"
      # Fix stupid Mac OS X.
      # See: http://www.joshstaiger.org/archives/2005/07/bash_profile_vs.html
      grep -q "source \"\$HOME/.bashrc\"" "$HOME/.bash_profile" || \
        printf "\n\nif [ -f \"$HOME/.bashrc\" ]; then\n  source \"$HOME/.bashrc\"\nfi\n\n"\
               >> "$HOME/.bash_profile"
      ;;
  esac
  # Don't silence this for now. It needs to be rewritten.
  bash $HOME/.dotfiles/install.sh
}


# Installs the Google Cloud SDK.
function install_google_cloud_sdk() {
  if [ ! -d "$HOME/google-cloud-sdk" ]; then
    curl https://sdk.cloud.google.com | bash
  else
    $HOME/google-cloud-sdk/bin/gcloud components update --quiet
  fi
  $HOME/google-cloud-sdk/bin/gcloud components update --quiet \
                                    app \
                                    app-engine-java \
                                    pkg-core \
                                    pkg-go \
                                    pkg-java \
                                    pkg-python \
                                    preview
}


# Installs node, npm, and bower.
#
# @param {version} String version for node (git tag).
function install_node() {
  # This version of node is not installed system-wide. It is local to the user.
  # and hence requires updating the PATH environment variable. .dotfiles handles
  # this.
  version=$1

  info "Installing node $version"
  sync_git_repo github.com/joyent/node

  # TODO(yesudeep): Add version detection.
  if ! command -v 'node' >& /dev/null; then
    pushdir $src_dir/github.com/joyent/node
    git checkout ${version} >> $logfile 2>&1
    info "Configuring node"
    ./configure --prefix=$HOME/var >> $logfile 2>&1
    info "Compiling node"
    make -j $MAKE_PAR_COUNT >> $logfile 2>&1
    info "Installing node"
    make install >> $logfile 2>&1
    info "Cleaning up to save disk space"
    make clean >> $logfile 2>&1
    popdir
  fi
  info "Installing additional node packages: $npm_packages"
  npm install -g $npm_packages >> $logfile 2>&1
  npm update >> $logfile 2>&1
}


# Installs tup.
#
# @param {version} A string version (git tag) to install.
function install_tup() {
  # Tup is installed system-wide.
  version="$1"

  info "Installing tup $version"
  sync_git_repo github.com/gittup/tup
  pushdir $src_dir/github.com/gittup/tup
  git checkout $version >> $logfile 2>&1
  ./bootstrap.sh >> $logfile 2>&1
  cp tup $HOME/var/bin
  git checkout master
  popdir
}


# Installs fish shell
#
# @param {version} The version to install (git tag or commit SHA-1 digest).
function install_fish_shell() {
  # Fish is installed system-wide.
  version=$1
  have_version=`fish --version 2>&1 | awk '{ print $3 }' | awk -F'-' '{ print $1 }' | tr -d '\r'`
  have_version=`echo $have_version | awk -F. '{ print $1.$2.$3 }'`
  required_version=`echo $version | awk -F. '{ print $1.$2.$3 }'`

  if ! command -v "fish" &>/dev/null || [[ "$required_version" -gt "$have_version" ]]; then
    info "Installing fish $version"
    sync_git_repo github.com/fish-shell/fish-shell
    pushdir $HOME/src/github.com/fish-shell/fish-shell
    git checkout ${version}
    autoreconf
    ./configure && make -j $MAKE_PAR_COUNT
    case "$OSTYPE" in
      "linux-gnu" )
        # Preparation
        info "Building fish"
        sudo make install
        ;;
      "darwin"* )
        info "Building fish"
        make install
        ;;
    esac
    grep -q "/usr/local/bin/fish" /etc/shells || \
      (printf "/usr/local/bin/fish\n" | sudo tee -a /etc/shells)
    git checkout master
    popdir
  fi
}


# Install and configure protocol-buffer compiler.
#
# @param {version} Version string for the required version of the protobuf
#    compiler.
function install_protobuf_compiler() {
  # Protoc compiler is installed system-wide.
  version=$1
  have_version=`protoc --version 2>&1 | awk '{ print $2 }'`

  compare_versions $version $have_version
  op=$?
  if ! command -v "protoc" &>/dev/null || [[ $op == 1 ]]; then
    info "Installing protobuf compiler $version"
    download \
      http://github.com/google/protobuf/releases/download/v${version}/protobuf-${version}.tar.bz2 \
      /tmp/protobuf-${version}.tar.bz2

    pushdir /tmp
    tar jxvf protobuf-${version}.tar.bz2 >> $logfile 2>&1
    pushdir protobuf-${version}

    info "Configuring Protobuf compiler"
    ./configure  >> $logfile 2>&1

    info "Compiling Protoc compiler"
    make -j $MAKE_PAR_COUNT >> $logfile 2>&1

    info "Installing Protoc compiler"
    sudo make install >> $logfile 2>&1
    popdir
    popdir

    # On Linux, sometimes the protoc compiler is not able to find shared
    # libraries after installation, and you may encounter errors like: "protoc:
    # error while loading shared libraries...".  This occurs when ld.so.cache
    # is stale. Running ldconfig creates necessary links and updates cache.
    #
    # OS X does not have an ldconfig executable, therefore, we test first
    # whether ldconfig is available. Also, it's likely this error is
    # Linux-specific.
    if command -v "ldconfig" &>/dev/null; then
      sudo ldconfig
    fi
  fi
}


# Install and configure java.
function configure_java() {
  # Update java configuration. Keep this at the end. It prompts for a response
  # and breaks stuff that comes after it for some reason.
  case "$OSTYPE" in
    "linux-gnu" )
      sudo update-alternatives --config java
      ;;
    "darwin"* )
      echo "Unimplemented"
      ;;
  esac
}


# Runs all tests to make this script bulletproof.
function run_tests() {
  # Run tests
  # argument table format:
  # testarg1   testarg2     expected_relationship
  echo "The following tests should pass"
  while read -r test
  do
    test_compare_versions $test
  done << EOF
1            1            =
2.1          2.2          <
3.0.4.10     3.0.4.2      >
4.08         4.08.01      <
3.2.1.9.8144 3.2          >
3.2          3.2.1.9.8144 <
1.2          2.1          <
2.1          1.2          >
5.6.7        5.6.7        =
1.01.1       1.1.1        =
1.1.1        1.01.1       =
1            1.0          =
1.0          1            =
1.0.2.0      1.0.2        =
1..0         1.0          =
1.0          1..0         =
EOF

  echo "The following test should fail (test the tester)"
  test_compare_versions 1 1 '>'
}


# Installs required software.
function install_all() {
  rotate_logfile "Starting installation: $now\nTo view logs: tail -f $logfile\n" $logfile
  sysinfo=`uname -a`
  info "System info: $sysinfo"

  # Install operating-system specific packages.
  case "$OSTYPE" in
    "linux-gnu")
      # Preparation
      info "Preparing to install"
      if [ ! command -v 'aptitude' 2>/dev/null ]; then
        info "Installing aptitude"
        sudo apt-get -y install aptitude | tee -a $logfile
        info "Checking for updates"
        sudo aptitude update | tee -a $logfile
        info "Upgrading packages"
        sudo aptitude -y full-upgrade | tee -a $logfile
      fi
      info "Installing build dependencies"
      sudo apt-get -y build-dep emacs24 fish | tee -a $logfile
      install_linux_packages $linux_packages
    ;;
    "darwin"*)
      if prompt_yes_no "Install Homebrew? [Y/n]"; then
        info "Please install XCode before proceeding. https://developer.apple.com/xcode/"
        if prompt_yes_no "Are you done installing xcode? [Y/n]"; then
          install_xcode_tools
          info "Please wait for the Xcode tools to be installed before proceeding."
          sudo xcodebuild -license
          install_homebrew
          # Apparently, sometimes this doesn't get installed, but we need it.
          brew install wget >> $logfile 2>&1
          install_brew_packages $brew_packages
          # OS X Fuse requires the brew packages to have been fetched and
          # installed.
          install_osxfuse "2.7.3"
        fi
      fi
      ;;
  esac

  # Install packages.
  install_go "1.5.1" $additional_go_packages

  return
  # install_watchman "v3.0.0"
  # install_buck "5a6d5d00d7f3be1329bf501c710ffa409ecea3d8"
  # install_android_sdk "r24.0.2" $android_packages
  install_tmux "1.9" "a" "2.0.21" "5.9"
  install_python_packages $python_packages
  install_ack
  # install_protobuf_compiler "2.6.1"
  # install_dart_sdk stable 44672 "1.9.1"
  # install_node "v0.11.14"
  # install_google_cloud_sdk
  # install_tup "1de2e9e0d7ce65f0ba90d1304c07ddbc0a6a2dc4" #"v0.7.3"
  install_fish_shell "2.2.0" # "bb01e5f81a02d45da654c597ca4a983fc152e4f8"
  configure_java
  install_shell_config
  install_emacs_config
}


# Check whether the callee user is non-root.
assert_non_root_user

# Parse command line arguments and initialize.
while [ $# -ne 0 ]; do
  case $1 in
    -h|--help)
      show_usage
      exit 0 ;;
    -U|--uninstall)
      echo "error: not implemented"
      exit 1 ;;
    -T|--run-tests|--run-tests)
      run_tests
      exit 0 ;;
    -*)
      echo "error: unsupported option: '$1'"
      show_usage
      exit 1 ;;
  esac
  shift
done

# Trap SIGINT.
# See: http://redsymbol.net/articles/bash-exit-traps/
function finish() {
  exit 1
}
trap finish EXIT


show_preamble
if prompt_yes_no "Proceed with installation? [Y/n]"; then
  install_all
  show_epilog
fi;

exit 0
