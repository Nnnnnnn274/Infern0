//
//  ipadecryptor.h
//  Cyanide private/in-dev IPA decryptor scaffold.
//
//  Goal: keep the core "decrypt an installed FairPlay IPA" flow local to the
//  device. v0 wires app discovery + Mach-O encryption probing first; task-port
//  minting, mach_vm dumping, and IPA zip writing land behind the same API.
//

#ifndef ipadecryptor_h
#define ipadecryptor_h

#import <stdbool.h>

#ifdef __OBJC__
#import <Foundation/Foundation.h>

NSArray<NSDictionary<NSString *, NSString *> *> *ipadecryptor_installed_apps(void);
NSString *ipadecryptor_display_name_for_bundle(NSString *bundleID);
NSString *ipadecryptor_default_output_directory(void);
NSString *ipadecryptor_app_store_account_summary(void);
bool ipadecryptor_has_app_store_account(void);
bool ipadecryptor_login_app_store(NSString *email,
                                  NSString *password,
                                  NSString *authCode,
                                  NSString **messageOut);
void ipadecryptor_clear_app_store_account(void);

NSDictionary<NSString *, NSString *> *ipadecryptor_resolve_app_store_input(NSString *input,
                                                                           NSString **messageOut);
bool ipadecryptor_download_app_store_ipa(NSString *input,
                                         NSString **downloadedPathOut,
                                         NSString **messageOut);

bool ipadecryptor_probe_installed_app(NSString *bundleID, NSString **messageOut);
bool ipadecryptor_start_decrypt_installed_app(NSString *bundleID, NSString **messageOut);

#endif /* __OBJC__ */

#endif /* ipadecryptor_h */
