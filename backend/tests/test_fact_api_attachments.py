import unittest


class AttachmentTests(unittest.TestCase):
    def test_only_bounded_pdf_or_entity_free_xml_are_accepted(self):
        from app.modules.facturacion.attachments import validate_file
        self.assertEqual(validate_file(b'%PDF-1.7\nexample','PDF'),'application/pdf')
        self.assertEqual(validate_file(b'<Invoice><ID>F001-1</ID></Invoice>','XML'),'application/xml')
        for data,kind in [(b'not a pdf','PDF'),(b'<broken','XML'),
            (b'<!DOCTYPE doc [<!ENTITY x "a">]><doc>&x;</doc>','XML'),(b'a'*(5*1024*1024+1),'PDF')]:
            with self.subTest(kind=kind),self.assertRaises(ValueError):validate_file(data,kind)
