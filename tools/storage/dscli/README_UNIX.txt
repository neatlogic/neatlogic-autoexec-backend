    IBM(R) System Storage(R) DS Command Line Interface
           for UNIX(R) or Linux(R) Host Systems

                   README
----------------------------------------------------------------
Contents

1.0 About this README file
1.1 Who should read this README file
1.2 Help contacts
2.0 Where to find more information
3.0 Contents of UNIX/Linux CLI package
4.0 Notices
5.0 Trademarks and service marks

---------------------------------------------------------------
1.0 About this README file

    This README file tells you where to find user information
    about the IBM System Storage DS Command Line
    Interface (CLI) User's Guide and lists the contents of the
    CLI package for UNIX or Linux host system.


1.1 Who should read this README file


    This README file is intended for system administrators
    who are familiar with the UNIX or Linux environment and
    who need to use the DS CLI to work with the IBM
    System Storage DS6000, DS8000 and 2105.


1.2 Help contacts


    1.  For administrative or non-technical support:

        1-877-426-6006 (Please listen to voice prompts)

        (Call this number if you have questions about your
         invoices, hardware or software order, hardware
         maintenance, service contracts, and commercial
         or state and local support for your system.)
    

    2.  Business Partner Support Operations:
        
        1-800-426-9990

    3.  Federal Government Support Operations:
    
        1-800-333-6705

---------------------------------------------------------------
2.0 Where to find more information

    See the IBM System Storage DS Command Line Interface
    User's Guide for detailed descriptions of the
    following:

        o   Using the System Storage DS CLI and commands
        o   Understanding the System Storage DS CLI

 	See the IBM System Storage DS8000 Messages Reference
	and the IBM System Storage DS6000 Messages Reference
	for detailed descriptions of DS CLI command messages.
	
	User's guide and message reference information
	are available at http://publib.boulder.ibm.com/
	infocenter/dsichelp/ds8000ic/index.jsp.
    They are also installed with the DS CLI as
    DSCLI.pdf, DS8000Messages.pdf, and DS6000Messages.pdf.

---------------------------------------------------------------
3.0 Contents of UNIX/Linux CLI package
    
    The UNIX/Linux CLI package contains the following files and 
    directories:

    README_UNIX.txt
    dscli
    DSCLI.pdf
    DS8000Messages.pdf
    DS6000Messages.pdf
    bin/
        lshostvol.sh
        lshostvolSDD.sh
        rsInquiryLinux.exe (Linux only)
        wbCsLinuxDPO.exe (Linux only)
        rsInquiryHP11.exe (HP-UX only)
    lib/
        CLI.CFG
        dsclihelp.jar
        dscli.jar
        ESSNIClient.jar
        hwmcaapi.jar
        ibmjsse.jar
        logger.jar
        rmcapi.jar
        ssgclihelp.jar
        ssgfrmwk.jar
        xalan.jar
        xerces.jar
    profile/
        dscli.profile
    _uninst/
        .com.zerog.registry.xml
        InstallScript.iap_xml
        uninstaller
        uninstaller.lax
        installvariables.properties
        uninstaller.jar
        

--------------------------------------------------------------
4.0 Notices


    This information was developed for products and
    services offered in the U.S.A.

    IBM may not offer the products, services,or features
    discussed in this document in other countries. Consult
    your local IBM representative for information on the
    products and services currently available in your area.
    Any reference to an IBM product, program, or service
    is not intended to state or imply that only that IBM
    product, program, or service may be used. Any
    functionally equivalent product, program, or service
    that does not infringe any IBM intellectual property
    right may be used instead. However, it is the user's
    responsibility to evaluate and verify the operation
    of any non-IBM product, program,or service.

    IBM may have patents or pending patent applications
    covering subject matter described in this document.
    The furnishing of this document does not give you
    any license to these patents. You can send license
    inquiries, in writing, to:

        IBM Director of Licensing
        IBM Corporation
        North Castle Drive
        Armonk, NY 10504-1785
        U.S.A.

    For license inquiries regarding double-byte (DBCS)
    information, contact the IBM Intellectual Property
    Department in your country or send inquiries, in
    writing, to:

        IBM World Trade Asia Corporation
        Licensing
        2-31 Roppongi 3-chome, Minato-ku
        Tokyo 106, Japan

    The following paragraph does not apply to the United
    Kingdom or any other country where such provisions
    are inconsistent with local law:

    INTERNATIONAL BUSINESS MACHINES CORPORATION PROVIDES
    THIS PUBLICATION "AS IS" WITHOUT WARRANTY OF ANY KIND,
    EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED
    TO, THE IMPLIED WARRANTIES OF NON-INFRINGEMENT,
    MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
    Some states do not allow disclaimer of express or
    implied warranties in certain transactions, therefore,
    this statement may not apply to you.

    This information could include technical inaccuracies
    or typographical errors. Changes are periodically
    made to the information herein; these changes will be
    incorporated in new editions of the publication. IBM
    may make improvements and/or changes in the product(s)
    and/or the program(s) described in this publication
    at any time without notice.

    IBM may use or distribute any of the information you
    supply in any way it believes appropriate without
    incurring any obligation to you.

    Any performance data contained herein was determined
    in a controlled environment. Therefore, the results
    obtained in other operating environments may vary
    significantly. Some measurements may have been made
    on development-level systems and there is no
    guarantee that these measurements will be the same
    on generally available systems. Furthermore, some
    measurement may have been estimated through
    extrapolation. Actual results may vary. Users of this
    document should verify the applicable data for their
    specific environment.

    Information concerning non-IBM products was obtained
    from the suppliers of those products, their published
    announcements or other publicly available sources.
    IBM has not tested those products and cannot confirm
    the accuracy of performance, compatibility or any
    other claims related to non-IBM products. Questions
    on the capabilities of non-IBM products should be
    addressed to the suppliers of those products.

    This information contains examples of data and reports
    used in daily business operations. To illustrate them
    as completely as possible, the examples include the
    names of individuals, companies, brands, and products.
    All of these names are fictitious and any similarity
    to the names and addresses used by an actual business
    enterprise is entirely coincidental.

    If you are viewing this information softcopy, the
    photographs and color illustrations may not appear.

--------------------------------------------------------------
5.0 Trademarks and service marks


    The following terms are trademarks of International
    Business Machines Corporation in the United States,
    other countries, or both:

    DS6000
    DS8000
    IBM
    System Storage

    UNIX is a registered trademark of The Open Group in
    the United States and other countries.
    
    Linux is a trademark of Linus Torvalds in the United
    States, other countries, or both.

    Other company, product, and service names may be
    trademarks or service marks of others.


--------------------------------------------------------------
(c) Copyright 2020 International Business Machines
    Corp. All rights reserved.


Note to U.S. Government Users Restricted Rights--Use duplication or
disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
