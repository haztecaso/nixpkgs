{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.openldap;
  openldap = cfg.package;
  configDir = if cfg.configDir != null then cfg.configDir else "/etc/openldap/slapd.d";

  ldapValueType = let
    singleLdapValueType = types.oneOf [
      types.str
      (types.submodule {
        options = {
          path = mkOption {
            type = types.path;
            description = ''
              A path containing the LDAP attribute. This is included at run-time, so
              is recommended for storing secrets.
            '';
          };
        };
      })
      (types.submodule {
        options = {
          base64 = mkOption {
            type = types.str;
            description = ''
              A base64-encoded LDAP attribute. Useful for storing values which
              contain special characters (e.g. newlines) in LDIF files.
            '';
          };
        };
      })
    ];
  in types.either singleLdapValueType (types.listOf singleLdapValueType);

  ldapAttrsType =
    let
      options = {
        attrs = mkOption {
          type = types.attrsOf ldapValueType;
          default = {};
          description = "Attributes of the parent entry.";
        };
        children = mkOption {
          # Hide the child attributes, to avoid infinite recursion in e.g. documentation
          # Actual Nix evaluation is lazy, so this is not an issue there
          type = let
            hiddenOptions = lib.mapAttrs (name: attr: attr // { visible = false; }) options;
          in types.attrsOf (types.submodule { options = hiddenOptions; });
          default = {};
          description = "Child entries of the current entry, with recursively the same structure.";
          example = lib.literalExample ''
          {
            "cn=schema" = {
              # The attribute used in the DN must be defined
              attrs = { cn = "schema"; };
              children = {
                # This entry's DN is expanded to "cn=foo,cn=schema"
                "cn=foo" = { ... };
              };
              # These includes are inserted after "cn=schema", but before "cn=foo,cn=schema"
              includes = [ ... ];
            };
          }
        '';
        };
        includes = mkOption {
          type = types.listOf types.path;
          default = [];
          description = ''
          LDIF files to include after the parent's attributes but before its children.
        '';
        };
      };
    in types.submodule { inherit options; };

  valueToLdif = attr: values: let
    listValues = if lib.isList values then values else lib.singleton values;
  in map (value:
    if lib.isAttrs value then
      if lib.hasAttr "path" value
      then "${attr}:< file://${value.path}"
      else "${attr}:: ${value.base64}"
    else "${attr}: ${lib.replaceStrings [ "\n" ] [ "\n " ] value}"
  ) listValues;

  attrsToLdif = dn: { attrs, children, includes, ... }: [''
    dn: ${dn}
    ${lib.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList valueToLdif attrs))}
  ''] ++ (map (path: "include: file://${path}\n") includes) ++ (
    lib.flatten (lib.mapAttrsToList (name: value: attrsToLdif "${name},${dn}" value) children)
  );
in {
  imports = let
    deprecationNote = "This option is removed due to the deprecation of `slapd.conf` upstream. Please migrate to `services.openldap.settings`, see the release notes for advice with this process.";
  in [
    (lib.mkRemovedOptionModule [ "services" "openldap" "extraConfig" ] deprecationNote)
    (lib.mkRemovedOptionModule [ "services" "openldap" "extraDatabaseConfig" ] deprecationNote)
  ];
  options = {
    services.openldap = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "
          Whether to enable the ldap server.
        ";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.openldap;
        description = ''
          OpenLDAP package to use.

          This can be used to, for example, set an OpenLDAP package
          with custom overrides to enable modules or other
          functionality.
        '';
      };

      user = mkOption {
        type = types.str;
        default = "openldap";
        description = "User account under which slapd runs.";
      };

      group = mkOption {
        type = types.str;
        default = "openldap";
        description = "Group account under which slapd runs.";
      };

      urlList = mkOption {
        type = types.listOf types.str;
        default = [ "ldap:///" ];
        description = "URL list slapd should listen on.";
        example = [ "ldaps:///" ];
      };

      settings = mkOption {
        type = ldapAttrsType;
        description = "Configuration for OpenLDAP, in OLC format";
        example = lib.literalExample ''
          {
            attrs.olcLogLevel = [ "stats" ];
            children = {
              "cn=schema".includes = [
                 "\${pkgs.openldap}/etc/schema/core.ldif"
                 "\${pkgs.openldap}/etc/schema/cosine.ldif"
                 "\${pkgs.openldap}/etc/schema/inetorgperson.ldif"
              ];
              "olcDatabase={-1}frontend" = {
                attrs = {
                  objectClass = "olcDatabaseConfig";
                  olcDatabase = "{-1}frontend";
                  olcAccess = [ "{0}to * by dn.exact=uidNumber=0+gidNumber=0,cn=peercred,cn=external,cn=auth manage stop by * none stop" ];
                };
              };
              "olcDatabase={0}config" = {
                attrs = {
                  objectClass = "olcDatabaseConfig";
                  olcDatabase = "{0}config";
                  olcAccess = [ "{0}to * by * none break" ];
                };
              };
              "olcDatabase={1}mdb" = {
                attrs = {
                  objectClass = [ "olcDatabaseConfig" "olcMdbConfig" ];
                  olcDatabase = "{1}mdb";
                  olcDbDirectory = "/var/db/ldap";
                  olcDbIndex = [
                    "objectClass eq"
                    "cn pres,eq"
                    "uid pres,eq"
                    "sn pres,eq,subany"
                  ];
                  olcSuffix = "dc=example,dc=com";
                  olcAccess = [ "{0}to * by * read break" ];
                };
              };
            };
          };
        '';
      };

      # These options are translated into settings
      dataDir = mkOption {
        type = types.nullOr types.path;
        default = "/var/db/openldap";
        description = "The database directory.";
      };

      defaultSchemas = mkOption {
        type = types.nullOr types.bool;
        default = true;

        description = ''
          Include the default schemas core, cosine, inetorgperson and nis.
        '';
      };

      database = mkOption {
        type = types.nullOr types.str;
        default = "mdb";
        description = "Backend to use for the first database.";
      };

      suffix = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "dc=example,dc=org";
        description = ''
          Specify the DN suffix of queries that will be passed to the first
          backend database.
        '';
      };

      rootdn = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "cn=admin,dc=example,dc=org";
        description = ''
          Specify the distinguished name that is not subject to access control
          or administrative limit restrictions for operations on this database.
        '';
      };

      rootpw = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Password for the root user.Using this option will store the root
          password in plain text in the world-readable nix store. To avoid this
          the <literal>rootpwFile</literal> can be used.
        '';
      };

      rootpwFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Password file for the root user.

          If the deprecated <literal>extraConfig</literal> or
          <literal>extraDatabaseConfig</literal> options are set, this should
          contain <literal>rootpw</literal> followed by the password
          (e.g. <literal>rootpw thePasswordHere</literal>).

          Otherwise the file should contain only the password (no trailing
          newline or leading <literal>rootpw</literal>).
        '';
      };

      logLevel = mkOption {
        type = types.nullOr (types.coercedTo types.str (lib.splitString " ") (types.listOf types.str));
        default = null;
        example = literalExample "[ \"acl\" \"trace\" ]";
        description = "The log level.";
      };

      # This option overrides settings
      configDir = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Use this config directory instead of generating one from the
          <literal>settings</literal> option. Overrides all NixOS settings. If
          you use this option,ensure `olcPidFile` is set to `/run/slapd/slapd.conf`.
        '';
        example = "/var/db/slapd.d";
      };

      declarativeContents = mkOption {
        type = with types; either lines (attrsOf lines);
        default = {};
        description = ''
          Declarative contents for the first LDAP database, in LDIF format.

          Note a few facts when using it. First, the database
          <emphasis>must</emphasis> be stored in the directory defined by
          <code>dataDir</code>. Second, all <code>dataDir</code> will be erased
          when starting the LDAP server. Third, modifications to the database
          are not prevented, they are just dropped on the next reboot of the
          server. Finally, performance-wise the database and indexes are rebuilt
          on each server startup, so this will slow down server startup,
          especially with large databases.
        '';
        example = ''
          dn: dc=example,dc=org
          objectClass: domain
          dc: example

          dn: ou=users,dc=example,dc=org
          objectClass = organizationalUnit
          ou: users

          # ...
        '';
      };
    };
  };

  meta = {
    maintainers = with lib.maintainters; [ mic92 kwohlfahrt ];
  };

  # TODO: Check that dataDir/declarativeContents/configDir all match
  # - deprecate declarativeContents = ''...'';
  # - no declarativeContents = ''...'' if dataDir == null;
  # - no declarativeContents = { ... } if configDir != null
  config = mkIf cfg.enable {
    warnings = let
      deprecations = [
        { old = "logLevel"; new = "attrs.olcLogLevel"; }
        { old = "defaultSchemas";
          new = "children.\"cn=schema\".includes";
          newValue = "[\n    ${lib.concatStringsSep "\n    " [
            "\${pkgs.openldap}/etc/schema/core.ldif"
            "\${pkgs.openldap}/etc/schema/cosine.ldif"
            "\${pkgs.openldap}/etc/schema/inetorgperson.ldif"
            "\${pkgs.openldap}/etc/schema/nis.ldif"
          ]}\n  ]"; }
        { old = "database"; new = "children.\"cn={1}${cfg.database}\""; newValue = "{ }"; }
        { old = "suffix"; new = "children.\"cn={1}${cfg.database}\".attrs.olcSuffix"; }
        { old = "dataDir"; new = "children.\"cn={1}${cfg.database}\".attrs.olcDbDirectory"; }
        { old = "rootdn"; new = "children.\"cn={1}${cfg.database}\".attrs.olcRootDN"; }
        { old = "rootpw"; new = "children.\"cn={1}${cfg.database}\".attrs.olcRootPW"; }
        { old = "rootpwFile";
          new = "children.\"cn={1}${cfg.database}\".attrs.olcRootPW";
          newValue = "{ path = \"${cfg.rootpwFile}\"; }";
          note = "The file should contain only the password (without \"rootpw \" as before)"; }
      ];
    in (flatten (map (args@{old, new, ...}: lib.optional ((lib.hasAttr old cfg) && (lib.getAttr old cfg) != null) ''
      The attribute `services.openldap.${old}` is deprecated. Please set it to
      `null` and use the following option instead:

        services.openldap.settings.${new} = ${args.newValue or (
          let oldValue = (getAttr old cfg);
          in if (isList oldValue) then "[ ${concatStringsSep " " oldValue} ]" else oldValue
        )}
    '') deprecations));

    assertions = [{
      assertion = !(cfg.rootpwFile != null && cfg.rootpw != null);
      message = "services.openldap: at most one of rootpw or rootpwFile must be set";
    }];

    environment.systemPackages = [ openldap ];

    # Literal attributes must always be set (even if other top-level attributres are deprecated)
    services.openldap.settings = {
      attrs = {
        objectClass = "olcGlobal";
        cn = "config";
        olcPidFile = "/run/slapd/slapd.pid";
      } // (lib.optionalAttrs (cfg.logLevel != null) {
        olcLogLevel = cfg.logLevel;
      });
      children = {
        "cn=schema" = {
          attrs = {
            cn = "schema";
            objectClass = "olcSchemaConfig";
          };
          includes = lib.optionals (cfg.defaultSchemas != null && cfg.defaultSchemas) [
            "${openldap}/etc/schema/core.ldif"
            "${openldap}/etc/schema/cosine.ldif"
            "${openldap}/etc/schema/inetorgperson.ldif"
            "${openldap}/etc/schema/nis.ldif"
          ];
        };
      } // (lib.optionalAttrs (cfg.database != null) {
        "olcDatabase={1}${cfg.database}".attrs = {
          # objectClass is case-insensitive, so don't need to capitalize ${database}
          objectClass = [ "olcdatabaseconfig" "olc${cfg.database}config" ];
          olcDatabase = "{1}${cfg.database}";
        } // (lib.optionalAttrs (cfg.suffix != null) {
          olcSuffix = cfg.suffix;
        }) // (lib.optionalAttrs (cfg.dataDir != null) {
          olcDbDirectory = cfg.dataDir;
        }) // (lib.optionalAttrs (cfg.rootdn != null) {
          olcRootDN = cfg.rootdn; # TODO: Optional
        }) // (lib.optionalAttrs (cfg.rootpw != null || cfg.rootpwFile != null) {
          olcRootPW = (if cfg.rootpwFile != null then { path = cfg.rootpwFile; } else cfg.rootpw); # TODO: Optional
        });
      });
    };

    systemd.services.openldap = {
      description = "LDAP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      preStart = let
        dbSettings = lib.filterAttrs (name: value: lib.hasPrefix "olcDatabase=" name) cfg.settings.children;
        dataDirs = lib.mapAttrs' (name: value: lib.nameValuePair value.attrs.olcSuffix value.attrs.olcDbDirectory)
          (lib.filterAttrs (_: value: value.attrs ? olcDbDirectory) dbSettings);
        settingsFile = pkgs.writeText "config.ldif" (lib.concatStringsSep "\n" (attrsToLdif "cn=config" cfg.settings));
      in ''
        mkdir -p /run/slapd
        chown -R "${cfg.user}:${cfg.group}" /run/slapd

        mkdir -p ${lib.escapeShellArg configDir} ${lib.escapeShellArgs (lib.attrValues dataDirs)}
        chown "${cfg.user}:${cfg.group}" ${lib.escapeShellArg configDir} ${lib.escapeShellArgs (lib.attrValues dataDirs)}

        ${lib.optionalString (cfg.configDir == null) (''
          rm -Rf ${configDir}/*
          ${openldap}/bin/slapadd -F ${configDir} -bcn=config -l ${settingsFile}
        '')}
        chown -R "${cfg.user}:${cfg.group}" ${lib.escapeShellArg configDir}

        ${if types.lines.check cfg.declarativeContents
          then (let
            dataFile = pkgs.writeText "ldap-contents.ldif" cfg.declarativeContents;
          in ''
            rm -rf ${lib.escapeShellArg cfg.dataDir}/*
            ${openldap}/bin/slapadd -F ${lib.escapeShellArg configDir} -l ${dataFile}
            chown -R "${cfg.user}:${cfg.group}" ${lib.escapeShellArg cfg.dataDir}
          '')
          else (let
            dataFiles = lib.mapAttrs (dn: contents: pkgs.writeText "${dn}.ldif" contents) cfg.declarativeContents;
          in ''
            ${lib.concatStrings (lib.mapAttrsToList (dn: file: let
              dataDir = lib.escapeShellArg (getAttr dn dataDirs);
            in ''
              rm -rf ${dataDir}/*
              ${openldap}/bin/slapadd -F ${lib.escapeShellArg configDir} -b ${dn} -l ${file}
              chown -R "${cfg.user}:${cfg.group}" ${dataDir}
            '') dataFiles)}
          '')
         }

        ${openldap}/bin/slaptest -u -F ${lib.escapeShellArg configDir}
      '';
      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([
          "${openldap}/libexec/slapd" "-u" cfg.user "-g" cfg.group "-F" configDir
          "-h" (lib.concatStringsSep " " cfg.urlList)
        ]);
        Type = "forking";
        PIDFile = cfg.settings.attrs.olcPidFile;
      };
    };

    users.users = lib.optionalAttrs (cfg.user == "openldap") {
      openldap = {
        group = cfg.group;
        isSystemUser = true;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "openldap") {
      openldap = {};
    };
  };
}
