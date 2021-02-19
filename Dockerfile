FROM opensuse/leap
RUN zypper -n in sudo tar daps
RUN useradd -m user && \
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
USER user
WORKDIR /home/user
