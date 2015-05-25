FROM 		phusion/baseimage
MAINTAINER 	Casey Bisson <casey.bisson@gmail.com

# Update Apt
RUN apt-get update

# Install some prereqs
RUN apt-get install -y curl unzip npm

# Get Consul
ADD https://dl.bintray.com/mitchellh/consul/0.5.1_linux_amd64.zip /tmp/consul.zip
RUN cd /bin && unzip /tmp/consul.zip && chmod +x /bin/consul && rm /tmp/consul.zip

# Get the Consul web UI
ADD https://dl.bintray.com/mitchellh/consul/0.5.1_web_ui.zip /tmp/webui.zip
RUN mkdir /ui && cd /ui && unzip /tmp/webui.zip && rm /tmp/webui.zip && mv dist/* . && rm -rf dist