prefix=/usr/local

araddclient:
	touch araddclient

install:
	install -D -m 0755 -t $(DESTDIR)$(prefix)/bin/ araddclient
	install -D -m 0644 -t $(DESTDIR)/lib/systemd/system araddclient.service araddclient.timer
	install -D -m 0644 -t $(DESTDIR)$(prefix)/share/doc/araddclient araddclient.conf.example
	install -D -m 0644 araddclient.conf.example $(DESTDIR)/etc/araddclient.conf
	install -d $(DESTDIR)/var/lib/araddclient
