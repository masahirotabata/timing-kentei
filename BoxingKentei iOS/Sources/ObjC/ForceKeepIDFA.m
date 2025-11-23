@import AdSupport;

void ForceKeepIDFA(void) {
  (void)[[ASIdentifierManager sharedManager] advertisingIdentifier].UUIDString;
  (void)[[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled];
}
