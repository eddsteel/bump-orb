FROM "cimg/base:current"
COPY "bump-orbs.sh" "/bump-orbs.sh"
ENTRYPOINT ["/bump-orbs.sh"]