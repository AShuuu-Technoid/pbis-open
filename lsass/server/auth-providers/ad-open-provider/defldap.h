/* Editor Settings: expandtabs and use 4 spaces for indentation
 * ex: set softtabstop=4 tabstop=8 expandtab shiftwidth=4: *
 * -*- mode: c, c-basic-offset: 4 -*- */

/*
 * Copyright © BeyondTrust Software 2004 - 2019
 * All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * BEYONDTRUST MAKES THIS SOFTWARE AVAILABLE UNDER OTHER LICENSING TERMS AS
 * WELL. IF YOU HAVE ENTERED INTO A SEPARATE LICENSE AGREEMENT WITH
 * BEYONDTRUST, THEN YOU MAY ELECT TO USE THE SOFTWARE UNDER THE TERMS OF THAT
 * SOFTWARE LICENSE AGREEMENT INSTEAD OF THE TERMS OF THE APACHE LICENSE,
 * NOTWITHSTANDING THE ABOVE NOTICE.  IF YOU HAVE QUESTIONS, OR WISH TO REQUEST
 * A COPY OF THE ALTERNATE LICENSING TERMS OFFERED BY BEYONDTRUST, PLEASE CONTACT
 * BEYONDTRUST AT beyondtrust.com/contact
 */

/*
 * Copyright (C) BeyondTrust Software. All rights reserved.
 *
 * Module Name:
 *
 *        provider-main.h
 *
 * Abstract:
 *
 *        BeyondTrust Security and Authentication Subsystem (LSASS)
 *
 *        Active Directory Authentication Provider
 *
 * Authors: Krishna Ganugapati (krishnag@likewisesoftware.com)
 *          Sriram Nambakam (snambakam@likewisesoftware.com)
 *          Wei Fu (wfu@likewisesoftware.com)
 *          Brian Dunstan (bdunstan@likewisesoftware.com)
 *          Kyle Stemen (kstemen@likewisesoftware.com)
 */

#ifndef DEFLDAP_H_
#define DEFLDAP_H_

DWORD
DefaultModeFindNSSArtefactByKey(
    IN PLSA_DM_LDAP_CONNECTION pConn,
    PCSTR          pszCellDN,
    PCSTR          pszNetBIOSDomainName,
    PCSTR          pszKeyName,
    PCSTR          pszMapName,
    DWORD          dwInfoLevel,
    LSA_NIS_MAP_QUERY_FLAGS dwFlags,
    PVOID*         ppNSSArtefactInfo
    );

DWORD
DefaultModeSchemaFindNSSArtefactByKey(
    IN PLSA_DM_LDAP_CONNECTION pConn,
    PCSTR          pszCellDN,
    PCSTR          pszNetBIOSDomainName,
    PCSTR          pszKeyName,
    PCSTR          pszMapName,
    DWORD          dwInfoLevel,
    LSA_NIS_MAP_QUERY_FLAGS dwFlags,
    PVOID*         ppNSSArtefactInfo
    );

DWORD
DefaultModeNonSchemaFindNSSArtefactByKey(
    IN PLSA_DM_LDAP_CONNECTION pConn,
    PCSTR          pszCellDN,
    PCSTR          pszNetBIOSDomainName,
    PCSTR          pszKeyName,
    PCSTR          pszMapName,
    DWORD          dwInfoLevel,
    LSA_NIS_MAP_QUERY_FLAGS dwFlags,
    PVOID*         ppNSSArtefactInfo
    );

DWORD
DefaultModeEnumNSSArtefacts(
    PLSA_DM_LDAP_CONNECTION pConn,
    PCSTR          pszCellDN,
    PCSTR          pszNetBIOSDomainName,
    PAD_ENUM_STATE pEnumState,
    DWORD          dwMaxNumNSSArtefacts,
    PDWORD         pdwNumNSSArtefactsFound,
    PVOID**        pppNSSArtefactInfoList
    );

DWORD
DefaultModeSchemaEnumNSSArtefacts(
    IN PLSA_DM_LDAP_CONNECTION pConn,
    PCSTR          pszCellDN,
    PCSTR          pszNetBIOSDomainName,
    PAD_ENUM_STATE pEnumState,
    DWORD          dwMaxNumNSSArtefacts,
    PDWORD         pdwNumNSSArtefactsFound,
    PVOID**        pppNSSArtefactInfoList
    );

DWORD
DefaultModeNonSchemaEnumNSSArtefacts(
    PLSA_DM_LDAP_CONNECTION pConn,
    PCSTR          pszCellDN,
    PCSTR          pszNetBIOSDomainName,
    PAD_ENUM_STATE pEnumState,
    DWORD          dwMaxNumNSSArtefacts,
    PDWORD         pdwNumNSSArtefactsFound,
    PVOID**        pppNSSArtefactInfoList
    );

#endif /*DEFLDAP_H_*/
