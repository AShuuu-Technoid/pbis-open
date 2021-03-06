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
    File:		TCarbonEvent.h
    
    Version:	1.1

	Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
				("Apple") in consideration of your agreement to the following terms, and your
				use, installation, modification or redistribution of this Apple software
				constitutes acceptance of these terms.  If you do not agree with these terms,
				please do not use, install, modify or redistribute this Apple software.

				In consideration of your agreement to abide by the following terms, and subject
				to these terms, Apple grants you a personal, non-exclusive license, under Apple?s
				copyrights in this original Apple software (the "Apple Software"), to use,
				reproduce, modify and redistribute the Apple Software, with or without
				modifications, in source and/or binary forms; provided that if you redistribute
				the Apple Software in its entirety and without modifications, you must retain
				this notice and the following text and disclaimers in all such redistributions of
				the Apple Software.  Neither the name, trademarks, service marks or logos of
				Apple Computer, Inc. may be used to endorse or promote products derived from the
				Apple Software without specific prior written permission from Apple.  Except as
				expressly stated in this notice, no other rights or licenses, express or implied,
				are granted by Apple herein, including but not limited to any patent rights that
				may be infringed by your derivative works or by other works in which the Apple
				Software may be incorporated.

				The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
				WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
				WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
				PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
				COMBINATION WITH YOUR PRODUCTS.

				IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
				CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
				GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
				ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
				OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
				(INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
				ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	Copyright ? 2000-2005 Apple Computer, Inc., All Rights Reserved
*/

#ifndef TCarbonEvent_H_
#define TCarbonEvent_H_

#include <Carbon/Carbon.h>

#include "HIFramework.h"

struct InvalidEventParameterType {};

template <class T> EventParamType EventDataType() throw( InvalidEventParameterType )
	{ throw InvalidEventParameterType(); return 0; }

template <> inline EventParamType EventDataType<WindowRef>() { return typeWindowRef; }
template <> inline EventParamType EventDataType<ControlRef>() { return typeControlRef; }
template <> inline EventParamType EventDataType<MenuRef>() { return typeMenuRef; }
template <> inline EventParamType EventDataType<DragRef>() { return typeDragRef; }

template <> inline EventParamType EventDataType<HIPoint>() { return typeHIPoint; }
template <> inline EventParamType EventDataType<HISize>() { return typeHISize; }
template <> inline EventParamType EventDataType<HIRect>() { return typeHIRect; }
template <> inline EventParamType EventDataType<Point>() { return typeQDPoint; }
template <> inline EventParamType EventDataType<Rect>() { return typeQDRectangle; }
template <> inline EventParamType EventDataType<RgnHandle>() { return typeQDRgnHandle; }

template <> inline EventParamType EventDataType<Boolean>() { return typeBoolean; }
template <> inline EventParamType EventDataType<UInt32>() { return typeUInt32; }

template <> inline EventParamType EventDataType<HICommand>() { return typeHICommand; }
template <> inline EventParamType EventDataType<HICommandExtended>() { return typeHICommand; }

class TCarbonEvent
{
public:
	// Construction/Destruction
	TCarbonEvent(
					UInt32				inClass,
					UInt32				inKind );
	TCarbonEvent(
					EventRef			inEvent );
	virtual ~TCarbonEvent();
	
	UInt32		GetClass() const
					{ return ::GetEventClass( fEvent ); }
	UInt32		GetKind() const
					{ return ::GetEventKind( fEvent ); };
	
	// Time
	void		SetTime(
					EventTime			inTime )
					{ ::SetEventTime( fEvent, inTime ); }
	EventTime	GetTime() const
					{ return ::GetEventTime( fEvent ); }
	UInt32		GetTimeAsTicks() const
					{ return EventTimeToTicks( GetTime() ); }
	
	// Retention
	void		Retain()
					{ ::RetainEvent( fEvent ); }
	void		Release()
					{ ::ReleaseEvent( fEvent ); }
	
	// Accessors
	operator	EventRef&()
					{ return fEvent; };
	EventRef	GetEventRef()
					{ return fEvent; }
	
	// Posting
	OSStatus 	PostToQueue(
					EventQueueRef		inQueue,
					EventPriority		inPriority = kEventPriorityStandard );

	// Parameters
	OSStatus	SetParameter(
					EventParamName		inName,
					EventParamType		inType,
					UInt32				inSize,
					const void*			inData );
	OSStatus	GetParameter(
					EventParamName		inName,
					EventParamType		inType,
					UInt32				inBufferSize,
					void*				outData );

	OSStatus	GetParameterType(
					EventParamName		inName,
					EventParamType*		outType );
	OSStatus	GetParameterSize(
					EventParamName		inName,
					UInt32*				outSize );

	// Simple parameters
	OSStatus	SetParameter(
					EventParamName		inName,
					Boolean				inValue );
	OSStatus	GetParameter(
					EventParamName		inName,
					Boolean*			outValue );

	OSStatus	SetParameter(
					EventParamName		inName,
					bool				inValue );
	OSStatus	GetParameter(
					EventParamName		inName,
					bool*				outValue );

	OSStatus	SetParameter(
					EventParamName		inName,
					Point				inPt );
	OSStatus	GetParameter(
					EventParamName		inName,
					Point*				outPt );

	OSStatus	SetParameter(
					EventParamName		inName,
					const HIPoint&		inPt );

	OSStatus	GetParameter(
					EventParamName		inName,
					HIPoint*			outPt );

	OSStatus	SetParameter(
					EventParamName		inName,
					const Rect&			inRect );
	OSStatus	GetParameter(
					EventParamName		inName,
					Rect*				outRect );

	OSStatus	SetParameter(
					EventParamName		inName,
					const HIRect&		inRect );
	OSStatus	GetParameter(
					EventParamName		inName,
					HIRect*				outRect );

	OSStatus	SetParameter(
					EventParamName		inName,
					const HISize&		inSize );
	OSStatus	GetParameter(
					EventParamName		inName,
					HISize*				outSize );

	OSStatus	SetParameter(
					EventParamName		inName,
					RgnHandle			inRegion );
	OSStatus	GetParameter(
					EventParamName		inName,
					RgnHandle*			outRegion );

	OSStatus	SetParameter(
					EventParamName		inName,
					WindowRef			inWindow );
	OSStatus	GetParameter(
					EventParamName		inName,
					WindowRef*			outWindow );

	OSStatus	SetParameter(
					EventParamName		inName,
					ControlRef			inControl );
	OSStatus	GetParameter(
					EventParamName		inName,
					ControlRef* outControl );

	OSStatus	SetParameter(
					EventParamName		inName,
					MenuRef				inMenu );
	OSStatus	GetParameter(
					EventParamName		inName,
					MenuRef*			outMenu );

	OSStatus	SetParameter(
					EventParamName		inName,
					DragRef				inDrag );
	OSStatus	GetParameter(
					EventParamName		inName,
					DragRef*			outDrag );

	OSStatus	SetParameter(
					EventParamName		inName,
					UInt32				inValue );
	OSStatus	GetParameter(
					EventParamName		inName,
					UInt32*				outValue );
	
	OSStatus	SetParameter(
					EventParamName		inName,
					const HICommand&	inValue );
	OSStatus	GetParameter(
					EventParamName		inName,
					HICommand*			outValue );
	OSStatus	SetParameter(
					EventParamName		inName,
					const
					HICommandExtended&	inValue );
	OSStatus	GetParameter(
					EventParamName		inName,
					HICommandExtended*	outValue );

	OSStatus	SetParameter(
					EventParamName		inName,
					const ControlPartCode&	inValue );
	OSStatus	GetParameter(
					EventParamName		inName,
					ControlPartCode*	outValue );

	// Template parameters
	template <class T> OSStatus SetParameter(
		EventParamName	inName,
		EventParamType	inType,
		const T&		inValue )
	{
		return SetParameter( inName, inType, sizeof( T ), &inValue );
	}
			
	template <class T> OSStatus GetParameter(
		EventParamName	inName,
		EventParamType	inType,
		T*				outValue )
	{
		return GetParameter( inName, inType, sizeof( T ), outValue );
	}
	
	template <class T> T GetParameter(
		EventParamName	inName )
	{
		T			outValue;
		
		verify_noerr( GetParameter( inName, EventDataType<T>(), sizeof( T ), &outValue ) );

		return outValue;
	}

	template <class T> void SetParameter(
		EventParamName	inName,
		const T&		inValue )
	{
		verify_noerr( SetParameter( inName, EventDataType<T>(), sizeof( T ), &inValue ) );
	}

	template <class T> T GetParameter(
		EventParamName	inName, EventParamType inType )
	{
		T			outValue;
		
		verify_noerr( GetParameter( inName, inType, sizeof( T ), &outValue ) );

		return outValue;
	}
	
private:
	EventRef	fEvent;
};

#endif // TCarbonEvent_H_
