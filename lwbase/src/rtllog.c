/* -*- mode: c; c-basic-offset: 4; indent-tabs-mode: nil; tab-width: 4 -*-
 * ex: set softtabstop=4 tabstop=8 expandtab shiftwidth=4: *
 * Editor Settings: expandtabs and use 4 spaces for indentation */

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
 *     rtllog.c
 *
 * Abstract:
 *
 *     RTL Logging
 *
 * Authors: Danilo Almeida (dalmeida@likewise.com)
 */

#include <lw/rtllog.h>

LW_RTL_LOG_CONTROL _LwRtlLogControl;

LW_VOID
LwRtlLogSetCallback(
    LW_IN LW_OPTIONAL LW_RTL_LOG_CALLBACK Callback,
    LW_IN LW_OPTIONAL LW_PVOID Context
    )
{
    _LwRtlLogControl.Callback = Callback;
    _LwRtlLogControl.Context = Context;
}

LW_VOID
LwRtlLogGetCallback(
    LW_OUT LW_OPTIONAL LW_RTL_LOG_CALLBACK *Callback,
    LW_OUT LW_OPTIONAL LW_PVOID *Context
    )
{
    if (Callback)
    {
        *Callback = _LwRtlLogControl.Callback;
    }

    if (Context)
    {
        *Context = _LwRtlLogControl.Context;
    }
}

LW_VOID
LwRtlLogSetLevel(
    LW_IN LW_RTL_LOG_LEVEL Level
    )
{
    _LwRtlLogControl.Level = Level;
}
