package com.agent.my_agent_app

import android.content.Context
import android.provider.ContactsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ContactsHandler(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "search" -> searchContacts(call.argument<String>("query") ?: "", result)
            "getById" -> getContactById(call.argument<String>("contactId") ?: "", result)
            "createContact" -> createContact(call, result)
            "deleteContact" -> deleteContact(call.argument<String>("contactId") ?: "", result)
            else -> result.notImplemented()
        }
    }

    private fun searchContacts(query: String, result: MethodChannel.Result) {
        try {
            val contacts = mutableListOf<Map<String, Any>>()
            val cursor = if (query.isEmpty()) {
                context.contentResolver.query(
                    ContactsContract.Contacts.CONTENT_URI,
                    arrayOf(
                        ContactsContract.Contacts._ID,
                        ContactsContract.Contacts.DISPLAY_NAME,
                        ContactsContract.Contacts.PHOTO_THUMBNAIL_URI,
                        ContactsContract.Contacts.HAS_PHONE_NUMBER
                    ),
                    null, null,
                    ContactsContract.Contacts.DISPLAY_NAME + " ASC"
                )
            } else {
                context.contentResolver.query(
                    ContactsContract.Contacts.CONTENT_URI,
                    arrayOf(
                        ContactsContract.Contacts._ID,
                        ContactsContract.Contacts.DISPLAY_NAME,
                        ContactsContract.Contacts.PHOTO_THUMBNAIL_URI,
                        ContactsContract.Contacts.HAS_PHONE_NUMBER
                    ),
                    ContactsContract.Contacts.DISPLAY_NAME + " LIKE ?",
                    arrayOf("%$query%"),
                    ContactsContract.Contacts.DISPLAY_NAME + " ASC"
                )
            }

            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts._ID))
                    val name = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME))
                    val thumb = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts.PHOTO_THUMBNAIL_URI))
                    val hasPhone = it.getInt(it.getColumnIndexOrThrow(ContactsContract.Contacts.HAS_PHONE_NUMBER)) > 0

                    contacts.add(mapOf(
                        "contactId" to id,
                        "displayName" to (name ?: ""),
                        "thumbnailUri" to (thumb ?: ""),
                        "hasPhoneNumber" to hasPhone
                    ))
                }
            }
            result.success(contacts)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "通讯录权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun getContactById(contactId: String, result: MethodChannel.Result) {
        try {
            val contact = mutableMapOf<String, Any>(
                "contactId" to contactId,
                "displayName" to "",
                "phones" to mutableListOf<Map<String, String>>(),
                "emails" to mutableListOf<Map<String, String>>(),
                "organization" to "",
                "addresses" to mutableListOf<String>()
            )

            // Get display name and photo
            val nameCursor = context.contentResolver.query(
                ContactsContract.Contacts.CONTENT_URI,
                arrayOf(
                    ContactsContract.Contacts.DISPLAY_NAME,
                    ContactsContract.Contacts.PHOTO_THUMBNAIL_URI
                ),
                ContactsContract.Contacts._ID + " = ?",
                arrayOf(contactId),
                null
            )
            nameCursor?.use {
                if (it.moveToFirst()) {
                    contact["displayName"] = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME)) ?: ""
                    contact["thumbnailUri"] = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts.PHOTO_THUMBNAIL_URI)) ?: ""
                }
            }

            // Get phone numbers
            val phoneCursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                    ContactsContract.CommonDataKinds.Phone.LABEL
                ),
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID + " = ?",
                arrayOf(contactId),
                null
            )
            val phones = mutableListOf<Map<String, String>>()
            phoneCursor?.use {
                while (it.moveToNext()) {
                    val number = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)) ?: ""
                    val type = it.getInt(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.TYPE))
                    val label = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.LABEL)) ?: ""
                    val typeStr = when (type) {
                        ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE -> "mobile"
                        ContactsContract.CommonDataKinds.Phone.TYPE_HOME -> "home"
                        ContactsContract.CommonDataKinds.Phone.TYPE_WORK -> "work"
                        else -> label
                    }
                    phones.add(mapOf("number" to number, "type" to typeStr))
                }
            }
            contact["phones"] = phones

            // Get emails
            val emailCursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Email.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Email.ADDRESS,
                    ContactsContract.CommonDataKinds.Email.TYPE,
                    ContactsContract.CommonDataKinds.Email.LABEL
                ),
                ContactsContract.CommonDataKinds.Email.CONTACT_ID + " = ?",
                arrayOf(contactId),
                null
            )
            val emails = mutableListOf<Map<String, String>>()
            emailCursor?.use {
                while (it.moveToNext()) {
                    val addr = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.ADDRESS)) ?: ""
                    val type = it.getInt(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.TYPE))
                    val label = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.LABEL)) ?: ""
                    val typeStr = when (type) {
                        ContactsContract.CommonDataKinds.Email.TYPE_HOME -> "home"
                        ContactsContract.CommonDataKinds.Email.TYPE_WORK -> "work"
                        else -> label
                    }
                    emails.add(mapOf("address" to addr, "type" to typeStr))
                }
            }
            contact["emails"] = emails

            // Get organization
            val orgCursor = context.contentResolver.query(
                ContactsContract.Data.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Organization.COMPANY,
                    ContactsContract.CommonDataKinds.Organization.TITLE
                ),
                ContactsContract.Data.CONTACT_ID + " = ? AND " +
                    ContactsContract.Data.MIMETYPE + " = ?",
                arrayOf(contactId, ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE),
                null
            )
            orgCursor?.use {
                if (it.moveToFirst()) {
                    val company = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Organization.COMPANY)) ?: ""
                    val title = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Organization.TITLE)) ?: ""
                    contact["organization"] = if (title.isNotEmpty()) "$title @ $company" else company
                }
            }

            result.success(contact)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "通讯录权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun createContact(call: MethodCall, result: MethodChannel.Result) {
        try {
            val givenName = call.argument<String>("givenName") ?: ""
            val familyName = call.argument<String>("familyName") ?: ""
            val phone = call.argument<String>("phone") ?: ""
            val email = call.argument<String>("email") ?: ""

            val ops = ArrayList<android.content.ContentProviderOperation>()

            // Insert raw contact
            val rawContactIndex = 0
            ops.add(android.content.ContentProviderOperation
                .newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
                .build())

            // Insert name
            ops.add(android.content.ContentProviderOperation
                .newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, rawContactIndex)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, givenName)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, familyName)
                .build())

            // Insert phone if provided
            if (phone.isNotEmpty()) {
                ops.add(android.content.ContentProviderOperation
                    .newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, rawContactIndex)
                    .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
                    .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
                    .build())
            }

            // Insert email if provided
            if (email.isNotEmpty()) {
                ops.add(android.content.ContentProviderOperation
                    .newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, rawContactIndex)
                    .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, email)
                    .withValue(ContactsContract.CommonDataKinds.Email.TYPE, ContactsContract.CommonDataKinds.Email.TYPE_HOME)
                    .build())
            }

            context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
            result.success("联系人已创建: $givenName $familyName")
        } catch (e: SecurityException) {
            result.error("PERMISSION", "通讯录写入权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun deleteContact(contactId: String, result: MethodChannel.Result) {
        try {
            if (contactId.isEmpty()) {
                result.error("INVALID", "contactId 不能为空", null)
                return
            }
            val uri = ContactsContract.RawContacts.CONTENT_URI
                .buildUpon()
                .appendQueryParameter(ContactsContract.CALLER_IS_SYNCADAPTER, "true")
                .build()
            val deleted = context.contentResolver.delete(uri,
                ContactsContract.RawContacts.CONTACT_ID + " = ?",
                arrayOf(contactId))
            if (deleted > 0) {
                result.success("联系人已删除")
            } else {
                result.error("NOT_FOUND", "联系人不存在", null)
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION", "通讯录写入权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
