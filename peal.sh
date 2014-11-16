#!/bin/bash
source /root/ceal.sh
mess -t "Setup hostname & timezone"
mess "Set hostname ($hostname)"
echo $hostname > /etc/hostname
mess "Set local timezone ($timezone)"
ln -fs /usr/share/zoneinfo/$timezone /etc/localtime

mess -t "Uncomment locales"
for i in ${locale[@]}; do
    mess "Add locale $i"
    sed -i "s/^#$i/$i/g" /etc/locale.gen
done
mess "Generate locales"
locale-gen
mess "Set font as $font"
setfont $font

mess -t "Prepare for software installation"
#if [ ! "$pkgsymlink" == "" ]; then
#    mess "Relink /var/cache/pacman/pkg folder properly"
#    rm -rf /var/cache/pacman/pkg
#    ln -fs $pkgsymlink /var/cache/pacman/pkg
#fi
mess "Install yaourt"
curl -O aur.sh/aur.sh
chmod +x aur.sh
./aur.sh -si --asroot --noconfirm package-query yaourt
rm -r aur.sh package-query yaourt
#if [ $localaur -eq 1 ]; then
#    mess "Give 777 rights to /var/cache/pacman/pkg"
#    mkdir -p /mnt/var/cache/pacman/pkg
#    chmod 777 /mnt/var/cache/pacman/pkg
#    mess "Edit PKGDEST value in /etc/makepkg.conf file"
#    sed -i '/#PKGDEST/aPKGDEST=/var/cache/pacman/pkg' /etc/makepkg.conf
#    mess "Edit EXPORT value in /etc/yaourtrc file"
#    sed -i '/#EXPORT=/aEXPORT=1' /etc/yaourtrc
#fi
#if [ $localinstall -eq 1 -a "`grep '\[local64\]' /etc/pacman.conf`" == "" ]; then
#    mess "Edit pacman.conf to include local repositories"
#    echo -e "[local64]\nSigLevel = PackageRequired\nServer = file:///var/cache/pacman/pkg\n[local32]\nSigLevel = PackageRequired\nServer = file:///var/cache/pacman/pkg\n[local]\nSigLevel = PackageRequired\nServer = file:///var/cache/pacman/pkg" >> /etc/pacman.conf
#fi
mess "Add multilib via sed"
sed -i '/\[multilib\]/,+1s/#//' /etc/pacman.conf
mess "Update packages including multilib"
yaourt -Syy

mess -t "Install grub"
mess "Install grub to /boot"
pacman -S --noconfirm grub
mess "Install grub bootloader to $mbr mbr"
grub-install --target=i386-pc --recheck $mbr
mess "Install os-prober"
pacman -S --noconfirm os-prober
mess "Make grub config"
grub-mkconfig -o /boot/grub/grub.cfg

mess -t "Setup network connection"
if [ $netctl -eq 1 ]; then
    mess "Copy $profile template"
    cp /etc/netctl/examples/$profile /etc/netctl/
    mess "Configure network"
    sed -i -e "s/eth0/$interface/" -e "s/wlan0/$interface/" -e "s/^Address=.*/Address='$ip\/24'/" -e "s/192.168.1.1/$dns/" -e "s/^ESSID=.*/ESSID='$essid'/" -e "s/^Key=.*/Key='$key'/" /etc/netctl/$profile
    mess "Enable netctl $profile"
    netctl enable $profile
else
    mess "Enable dhcpcd"
    systemctl enable dhcpcd
fi

mess -t "Install all software"
for (( i = 0; i < ${#software[@]}; i++ )); do
    mess "Install ${softtitle[$i]} software ($((i+1))/${#software[@]})"
    yaourt -S --noconfirm ${software[$i]}
done
mess "Clean mess - remove orphans recursively"
pacman -Rns `pacman -Qtdq` --noconfirm || true

if [ ! "$windows" == "" ]; then
    mess -t "Copy windows fonts to linux"
    mess "Mount windows partition to /mnt/windows"
    mkdir -p /mnt/windows
    mount $windows /mnt/windows
    mess "Copy windows fonts to /usr/share/fonts/winfonts"
    mkdir -p /usr/share/fonts
    cp -r /mnt/windows/Windows/Fonts /usr/share/fonts/winfonts
    mess "Update fonts cache"
    fc-cache -fv
    mess "Unmount windows partition"
    umount $windows
fi

if [ ! "$service" == "" ]; then
    mess -t "Enable services"
    for s in ${service[@]}; do
        mess "Enable $s service"
        systemctl enable $s
    done
fi

if [ ! "$group" == "" ]; then
    mess -t "Create non-existing groups"
    for i in "${group[@]}"; do
        IFS=',' read -a grs <<< "$i"
        for j in "${grs[@]}"; do
            if [ "$(grep $j /etc/group)" == "" ]; then
                mess "Add group '$j'"
                groupadd $j
            fi
        done
    done
fi

mess -t "Quickly create users (need for chmod-ing git repos)"
for i in ${user[@]}; do
    mess "Create user $i"
    useradd -m -g users -s /bin/bash $i
done

if [ ! "$rootexec" == "" ]; then
    mess -t "Execute all BACKUP commands before messing with GIT"
    shopt -s dotglob
    for (( i = 0; i < ${#backupexec[@]}; i++ )); do
        mess "Execute '${backupexec[$i]}'"
        eval ${backupexec[$i]}
    done
    shopt -u dotglob
fi

if [ ! "$gitrepo" == "" ]; then
    mess -t "Clone github repositories"
    for (( i = 0; i < ${#gitrepo[@]}; i++ )); do
        mess "Clone ${gitrepo[$i]} repo"
        git clone https://github.com/${gitrepo[$i]}.git ${gitfolder[$i]}
        if [ ! "${gitmodule[$i]}" == "" ]; then
            mess "Pull submodules ${gitmodule[$i]}"
            cd ${gitfolder[$i]}
            git submodule update --init --recursive ${gitmodule[$i]}
            IFS=' ' read -a submods <<< "${gitmodule[$i]}"
            for j in "${submods[@]}"; do
                mess "Checkout submodule $j to master"
                cd ${gitfolder[$i]}/$j
                git checkout master
            done
            cd
        fi
        if [ ! "${gitrule[$i]}" == "" ]; then
            mess "SET chown '${gitrule[$i]}'"
            chown -R ${gitrule[$i]} ${gitfolder[$i]}
	    chown -R $main:users ${gitfolder[$i]}/.git
        fi
        if [ ! "${gitbranch[$i]}" == "" ]; then
            mess "Checkout to branch '${gitbranch[$i]}'"
            cd ${gitfolder[$i]}
            git checkout ${gitbranch[$i]}
            git remote set-url origin git@github.com:${gitrepo[$i]}.git
            cd
        fi
        if [ ! "${gitlink[$i]}" == "" ]; then
            mess "Merge all files (make symlinks)"
            shopt -s dotglob
            for f in $(ls -A ${gitfolder[$i]}/ | grep -v .git); do
                if [ -d ${gitlink[$i]}/$f ]; then
                    mess "Move $f folder from ${gitlink[$i]} to ${gitfolder[$i]} becaus it exists"
                    cp -npr ${gitlink[$i]}/$f/* ${gitfolder[$i]}/$f/ 2>/dev/null
                    rm -r ${gitlink[$i]}/$f
                fi
                mess "Make symlink from ${gitfolder[$i]}/$f to ${gitlink[$i]}/"
                ln -fs ${gitfolder[$i]}/$f ${gitlink[$i]}/
            done
            shopt -u dotglob
        fi
    done
fi

mess -t "Setup users"
mess "Prepare sudoers file for pasting entries"
echo -e "\n## Users configuration" >> /etc/sudoers
for (( i = 0; i < ${#user[@]}; i++ )); do
    mess "Add user ${user[$i]} to groups: '${group[$i]}'"
    usermod -G ${group[$i]} ${user[$i]}
    mess "Add user ${user[$i]} entry into /etc/sudoers"
    echo "${user[$i]} ALL=(ALL) ALL" >> /etc/sudoers
    if ! [ "${gitname[$i]}" == "" -a "${execs[$i]}" == "" ]; then
        cd /home/${user[$i]}
        mess "Prepare user-executed script for ${user[$i]} user"
        echo $'
        source ceal.sh
        mess -t "User executed script for ${user[$i]} user"
        ' > user.sh
        if [ ! "${gitname[$i]}" == "" ]; then
            mess "Add git configuration to user-executed script"
            echo $'
            mess "Configure git for ${user[$i]}"
            mess "Configure git user.name as ${gitname[$i]}"
            git config --global user.name ${gitname[$i]}
            mess "Configure git user.email as ${gitemail[$i]}"
            git config --global user.email ${gitemail[$i]}
            mess "Configure git merge.tool as ${gittool[$i]}"
            git config --global merge.tool ${gittool[$i]}
            mess "Configure git core.editor as ${giteditor[$i]}"
            git config --global core.editor ${giteditor[$i]}
            ' >> user.sh
        fi
        if [ ! "${execs[$i]}" == "" ]; then
            mess "Add user-based execs to user-executed script"
            echo -e ${execs[$i]} >> user.sh
        fi
        mess "Make executable (+x)"
        chmod +x user.sh
        mess "Copy ceal.sh there"
        cp /root/ceal.sh .
        mess "Execute user-executed script by ${user[$i]} user"
        mv .bash_profile .bash_profilecopy 2>/dev/null
        su -c ./user.sh -s /bin/bash ${user[$i]}
        mv .bash_profilecopy .bash_profile 2>/dev/null
        mess "Remove user.sh & ceal.sh scripts from home directory"
        rm {user,ceal}.sh
        cd
    fi
    mess "Set ${user[$i]} shell to ${shell[$i]}"
    chsh -s ${shell[$i]} ${user[$i]}
done

if [ ! "$sudoers" == "" ]; then
    mess -t "Add additional entries into /etc/sudoers"
    echo -e "\n## Additional configuration" >> /etc/sudoers
    for i in "${sudoers[@]}"; do
        mess "Add '$i' entry"
        echo $i >> /etc/sudoers
    done
fi

if [ ! "$rootexec" == "" ]; then
    mess -t "Execute all root commands"
    shopt -s dotglob
    for (( i = 0; i < ${#rootexec[@]}; i++ )); do
        mess "Execute '${rootexec[$i]}'"
        eval ${rootexec[$i]}
    done
    shopt -u dotglob
fi

mess -t "Setup all passwords"
mess -p "Setup ROOT password"
passwd
for i in ${user[@]}; do
    mess -p "Setup user ($i) password"
    passwd $i
done

mess -t "Finish installation"
mess "Remove all scripts"
rm /root/{ceal,peal}.sh
mess "Exit chroot (installed system -> live-cd)"
exit
