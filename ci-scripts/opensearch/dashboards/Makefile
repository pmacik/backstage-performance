TEMPLATE_FILE ?= rhdh-dashboard.mvp-cpt.template.ndjson
VARIANTS ?= mvp-cpt.default

.PHONY: clone-dashboards
clone-dashboards:
	OUT=rhdh-dashboard.mvp-cpt.all.ndjson; \
	rm -rvf $${OUT}; \
	for VARIANT in $(VARIANTS); do \
		INDEX_PATTERN="rhdh-performance.mvp-cpt-$${VARIANT}"; \
		python3 clone-dashboard.py $(TEMPLATE_FILE) mvp-cpt-$${VARIANT} --index-pattern "$${INDEX_PATTERN}"; \
	  cat rhdh-dashboard.mvp-cpt-$${VARIANT}.ndjson >> $${OUT}; \
	done;

.PHONY: generate-rhdh-dashboards
generate-rhdh-dashboard:
	$(MAKE) clone-dashboards VARIANTS="xs s m l xl legacy"
